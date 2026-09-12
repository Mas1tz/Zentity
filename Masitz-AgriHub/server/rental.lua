-- ============================================================
--  Masitz-AgriHub | server/rental.lua
--  Maskinudlejning (§25-§37): udlejning direkte fra AgriHub (NPC/
--  systemet) samt fremleje spiller-til-spiller via en fuld digital
--  kontrakt (godkend -> signér -> aktiv), unikke AGR-XXXXXX-ID'er.
--
--  PRIS-REGEL (§29): priser kommer ALTID friskt fra
--  Config.Agri.Rentals — ALDRIG fra klient-input, heller ikke ved
--  fremleje eller forlængelse.
--  UDLEVERINGS-REGEL (§31-§32): før en kontrakt er godkendt OG
--  signeret af begge parter, bliver nøglen ALDRIG udleveret.
-- ============================================================

AH = AH or {}

-- ─── HJÆLPEFUNKTIONER ───────────────────────────────────────────
local function FindSrcByIdentifier(identifier)
    for src, session in pairs(AH.Sessions) do
        if session.identifier == identifier then return src end
    end
    return nil
end

-- Server-autoritativ pris-opslag (§29). Returnerer nil + årsag hvis
-- maskinen ikke findes, eller er vinter-spærret.
local function ComputeRentalPrice(machine)
    local cfg = Config.Agri.Rentals[machine]
    if not cfg then return nil, 'Ukendt maskine.' end
    if cfg.winterOnly and not Config.Agri.IsWinter then
        return nil, ('%s kan kun lejes om vinteren.'):format(cfg.label)
    end
    return cfg
end

local function ClampDuration(hours)
    hours = tonumber(hours)
    local rules = Config.Agri.ContractRules
    if not hours or hours < rules.minDurationHours or hours > rules.maxDurationHours then
        return rules.defaultDurationHours
    end
    return math.floor(hours)
end

-- Genererer et unikt AGR-XXXXXX kontrakt-ID med kollisions-retry,
-- samme mønster som task-ID'er i server/tasks.lua.
local function GenerateContractId()
    for _ = 1, 5 do
        local id = AH.GenerateId('AGR')
        local exists = MySQL.scalar.await('SELECT 1 FROM agrihub_contracts WHERE contract_id = ? LIMIT 1', { id })
        if not exists then return id end
    end
    return nil
end

local function FindContract(contractId)
    return MySQL.single.await('SELECT * FROM agrihub_contracts WHERE contract_id = ? LIMIT 1', { contractId })
end

-- Lazy expiry (§ ingen baggrunds-loop nødvendig) — køres når en
-- spiller rent faktisk kigger på sine kontrakter.
local function ExpireStaleContracts()
    MySQL.update('UPDATE agrihub_contracts SET status = "expired" WHERE status = "active" AND expires_at IS NOT NULL AND expires_at <= NOW()', {})
end

-- ─── KATALOG (til NUI "Udlejning") ──────────────────────────────
lib.callback.register('masitz_agrihub:rental:catalog', function(src)
    if not AH.RequireSession(src) then return {} end

    local list = {}
    for machine, cfg in pairs(Config.Agri.Rentals) do
        if not cfg.winterOnly or Config.Agri.IsWinter then
            list[#list + 1] = { machine = machine, label = cfg.label, deposit = cfg.deposit, rent = cfg.rent }
        end
    end
    table.sort(list, function(a, b) return a.label < b.label end)

    return {
        machines = list,
        rules = Config.Agri.ContractRules,
    }
end)

-- ─── LEJ FRA AGRIHUB (NPC/systemet) — §25-§26 ───────────────────
lib.callback.register('masitz_agrihub:rental:npc:create', function(src, machine, paymentMethod, durationHours)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Du er ikke logget ind på AgriHub.' } end

    local priceCfg, err = ComputeRentalPrice(machine)
    if not priceCfg then return { success = false, msg = err } end

    if paymentMethod ~= 'cash' and paymentMethod ~= 'bank' then paymentMethod = 'bank' end
    durationHours = ClampDuration(durationHours)

    local xp = AH.GetXPlayer(src)
    if not xp then return { success = false, msg = 'Spillerdata ikke fundet.' } end

    local plate = AH.GenerateRentalPlate()
    if not plate then return { success = false, msg = 'Ingen ledige udlejnings-plader lige nu — prøv igen om lidt.' } end

    local total = priceCfg.deposit + priceCfg.rent
    if not AH.TryCharge(xp, paymentMethod, total) then
        return { success = false, msg = ('Du har ikke råd (%d kr. i depositum + leje).'):format(total) }
    end

    local contractId = GenerateContractId()
    if not contractId then
        AH.Pay(xp, paymentMethod, total)
        return { success = false, msg = 'Kunne ikke oprette kontrakt lige nu — prøv igen.' }
    end

    local ok = MySQL.insert.await(
        [[INSERT INTO agrihub_contracts
            (contract_id, owner_identifier, renter_identifier, vehicle_model, vehicle_plate,
             deposit, rent, payment_method, start_at, expires_at, status,
             owner_approved, renter_approved, owner_signed, renter_signed)
          VALUES (?, NULL, ?, ?, ?, ?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL ? HOUR), 'active', 1, 1, 1, 1)]],
        { contractId, session.identifier, machine, plate, priceCfg.deposit, priceCfg.rent, paymentMethod, durationHours }
    )

    if not ok then
        AH.Pay(xp, paymentMethod, total)
        return { success = false, msg = 'Kunne ikke oprette kontrakt lige nu — prøv igen.' }
    end

    AH.RegisterVehicle(plate, { src = src, type = 'rental', refId = contractId, model = machine })

    AH.LogAction('rentals', 'RENTAL_CREATED', src, {
        contractId = contractId, machine = machine, plate = plate,
        deposit = priceCfg.deposit, rent = priceCfg.rent, durationHours = durationHours,
    })

    return {
        success = true, contractId = contractId, plate = plate, model = machine,
        deposit = priceCfg.deposit, rent = priceCfg.rent,
        spawnCoords = Config.Agri.RentalSpawnCoords,
    }
end)

-- Klienten bekræfter at køretøjet faktisk er spawnet, FØR nøglen
-- udleveres — undgår at give en nøgle til et køretøj der ikke findes.
RegisterNetEvent('masitz_agrihub:rental:vehicleSpawned', function(plate)
    local src = source
    plate = AH.NormPlate(plate)
    local record = plate and AH.GetVehicleRecord(plate)
    if not record or record.src ~= src or record.type ~= 'rental' then return end

    AH.GiveKey(src, plate)
end)

-- ─── AFLEVERING (§35) — fuld valideringstjekliste ───────────────
lib.callback.register('masitz_agrihub:rental:return', function(src, plate)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Du er ikke logget ind på AgriHub.' } end

    plate = AH.NormPlate(plate)
    if not plate then return { success = false, msg = 'Ugyldig nummerplade.' } end

    local record = AH.GetVehicleRecord(plate)
    if not record or record.type ~= 'rental' or record.src ~= src then
        return { success = false, msg = 'Det er ikke dit lejede køretøj.' }
    end

    local contract = MySQL.single.await(
        'SELECT * FROM agrihub_contracts WHERE contract_id = ? AND vehicle_plate = ? LIMIT 1',
        { record.refId, plate }
    )
    if not contract then return { success = false, msg = 'Ingen kontrakt fundet for dette køretøj.' } end
    if contract.renter_identifier ~= session.identifier then
        AH.LogSecurity(src, 'rental_return_wrong_player', 'Forsøgte at aflevere en andens lejede køretøj.', { contractId = contract.contract_id })
        return { success = false, msg = 'Denne kontrakt tilhører ikke dig.' }
    end
    if contract.status ~= 'active' and contract.status ~= 'expired' then
        return { success = false, msg = 'Denne kontrakt er allerede afsluttet.' }
    end

    -- Korrekt køretøj + korrekt spiller: spilleren skal reelt sidde i
    -- køretøjet, og pladen skal matche den den blev udleveret med.
    local ped = GetPlayerPed(src)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        return { success = false, msg = 'Du skal sidde i køretøjet for at aflevere det.' }
    end
    local vehPlate = AH.NormPlate(GetVehicleNumberPlateText(veh))
    if vehPlate ~= plate then
        AH.LogSecurity(src, 'rental_return_plate_mismatch', 'Prøvede at aflevere med forkert plade.', { expected = plate, got = vehPlate })
        return { success = false, msg = 'Dette er ikke det lejede køretøj.' }
    end

    local zone = Config.Agri.RentalReturnZone
    local dist = #(GetEntityCoords(veh) - zone.coords)
    if dist > zone.distance then
        return { success = false, msg = 'Du er ikke ved afleveringszonen.' }
    end

    if contract.deposit_refunded == 0 then
        local xp = AH.GetXPlayer(src)
        if xp then AH.Pay(xp, contract.payment_method, contract.deposit) end
    end

    MySQL.update.await(
        'UPDATE agrihub_contracts SET status = "completed", deposit_refunded = 1 WHERE contract_id = ?',
        { contract.contract_id }
    )

    AH.RemoveKey(src, plate)
    AH.UnregisterVehicle(plate)

    -- Ved fremleje: giv nøglen tilbage til den oprindelige udlejer
    -- hvis de stadig er online.
    if contract.owner_identifier then
        local ownerSrc = FindSrcByIdentifier(contract.owner_identifier)
        if ownerSrc then AH.GiveKey(ownerSrc, plate) end
    end

    -- Server- og client-side entity-handles er IKKE de samme tal —
    -- vi skal sende net-ID'et, ikke det server-lokale handle.
    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerClientEvent('masitz_agrihub:rental:deleteVehicle', src, netId)

    AH.LogAction('rentals', 'RENTAL_RETURNED', src, { contractId = contract.contract_id, plate = plate })

    return { success = true, depositRefunded = contract.deposit }
end)

-- ─── FORLÆNGELSE (§34) — pris genberegnes ALTID server-side ────
lib.callback.register('masitz_agrihub:rental:extend', function(src, contractId, extraHours)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Du er ikke logget ind på AgriHub.' } end

    extraHours = math.floor(tonumber(extraHours) or 0)
    if extraHours <= 0 then return { success = false, msg = 'Ugyldigt antal timer.' } end

    local contract = FindContract(contractId)
    if not contract or contract.status ~= 'active' then
        return { success = false, msg = 'Ingen aktiv kontrakt fundet.' }
    end
    if contract.renter_identifier ~= session.identifier then
        return { success = false, msg = 'Denne kontrakt tilhører ikke dig.' }
    end

    local priceCfg = Config.Agri.Rentals[contract.vehicle_model]
    if not priceCfg then return { success = false, msg = 'Maskintypen findes ikke længere i systemet.' } end

    local rules = Config.Agri.ContractRules
    local totalHoursOk = MySQL.scalar.await(
        'SELECT TIMESTAMPDIFF(HOUR, start_at, DATE_ADD(expires_at, INTERVAL ? HOUR)) <= ? FROM agrihub_contracts WHERE contract_id = ?',
        { extraHours, rules.maxDurationHours, contractId }
    )
    if totalHoursOk == 0 then
        return { success = false, msg = ('Du kan maksimalt leje i %d timer i alt.'):format(rules.maxDurationHours) }
    end

    -- Pris pr. time udledes friskt af konfigurationens flade leje-pris
    -- ift. standard-lejeperioden — aldrig fra klient-input.
    local hourlyRate = priceCfg.rent / rules.defaultDurationHours
    local extensionCost = math.ceil(hourlyRate * extraHours)

    local xp = AH.GetXPlayer(src)
    if not xp then return { success = false, msg = 'Spillerdata ikke fundet.' } end
    if not AH.TryCharge(xp, contract.payment_method, extensionCost) then
        return { success = false, msg = ('Du har ikke råd til forlængelsen (%d kr.).'):format(extensionCost) }
    end

    MySQL.update.await(
        'UPDATE agrihub_contracts SET expires_at = DATE_ADD(expires_at, INTERVAL ? HOUR), rent = rent + ? WHERE contract_id = ?',
        { extraHours, extensionCost, contractId }
    )

    AH.LogAction('contracts', 'RENTAL_EXTENDED', src, { contractId = contractId, extraHours = extraHours, cost = extensionCost })

    return { success = true, cost = extensionCost, extraHours = extraHours }
end)

-- ─── OVERSIGT / KONTRAKTER (§27, §33) ───────────────────────────
lib.callback.register('masitz_agrihub:rental:list', function(src)
    local session = AH.RequireSession(src)
    if not session then return { asRenter = {}, asOwner = {} } end

    ExpireStaleContracts()

    local asRenter = MySQL.query.await(
        'SELECT * FROM agrihub_contracts WHERE renter_identifier = ? ORDER BY created_at DESC LIMIT 50',
        { session.identifier }
    ) or {}
    local asOwner = MySQL.query.await(
        'SELECT * FROM agrihub_contracts WHERE owner_identifier = ? ORDER BY created_at DESC LIMIT 50',
        { session.identifier }
    ) or {}

    return { asRenter = asRenter, asOwner = asOwner }
end)

-- ─── FREMLEJE SPILLER-TIL-SPILLER (§28, §31-§33) ────────────────
-- Opsæt: en spiller der allerede har en AKTIV kontrakt (fra AgriHub)
-- kan tilbyde den videre til en anden spiller. Prisen genberegnes
-- friskt fra Config.Agri.Rentals — udlejeren kan ALDRIG sætte sin
-- egen pris. Nøglen skifter FØRST hånd når begge parter har
-- godkendt OG signeret, og lejeren reelt har betalt.

-- BEMÆRK: opslag/tilbud kræver IKKE at modtageren allerede er logget ind
-- på AgriHub — kun at de er online på serveren. At kræve en aktiv
-- AgriHub-session for at kunne slå dem op gjorde det umuligt at skrive
-- deres ID hvis de ikke tilfældigvis havde tabletten åben i samme øjeblik.
-- Selve GODKENDELSEN/signeringen kræver stadig at DE selv logger ind.
lib.callback.register('masitz_agrihub:rental:p2p:lookupPlayer', function(src, query)
    if not AH.RequireSession(src) then return {} end
    query = tostring(query or ''):lower()
    if query == '' then return {} end

    local results = {}
    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        if pid and pid ~= src then
            local name = GetPlayerName(pid) or ''
            if tostring(pid) == query or name:lower():find(query, 1, true) then
                results[#results + 1] = { serverId = pid, name = name }
            end
        end
        if #results >= 10 then break end
    end
    return results
end)

lib.callback.register('masitz_agrihub:rental:p2p:create', function(src, sourceContractId, targetServerId)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Du er ikke logget ind på AgriHub.' } end

    local sourceContract = FindContract(sourceContractId)
    if not sourceContract or sourceContract.status ~= 'active' or sourceContract.renter_identifier ~= session.identifier then
        return { success = false, msg = 'Du har ikke en aktiv kontrakt med dette ID.' }
    end

    targetServerId = tonumber(targetServerId)
    local targetXp = targetServerId and AH.GetXPlayer(targetServerId)
    if not targetServerId or not targetXp then
        return { success = false, msg = 'Spilleren blev ikke fundet online. Tjek server-ID\'et.' }
    end
    if targetXp.identifier == session.identifier then
        return { success = false, msg = 'Du kan ikke fremleje til dig selv.' }
    end

    local priceCfg, err = ComputeRentalPrice(sourceContract.vehicle_model)
    if not priceCfg then return { success = false, msg = err } end

    local contractId = GenerateContractId()
    if not contractId then return { success = false, msg = 'Kunne ikke oprette kontrakt lige nu — prøv igen.' } end

    local durationHours = Config.Agri.ContractRules.defaultDurationHours

    MySQL.insert.await(
        [[INSERT INTO agrihub_contracts
            (contract_id, owner_identifier, renter_identifier, vehicle_model, vehicle_plate,
             deposit, rent, payment_method, start_at, expires_at, status,
             owner_approved, renter_approved, owner_signed, renter_signed)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW(), DATE_ADD(NOW(), INTERVAL ? HOUR), 'pending', 1, 0, 0, 0)]],
        {
            contractId, session.identifier, targetXp.identifier,
            sourceContract.vehicle_model, sourceContract.vehicle_plate,
            priceCfg.deposit, priceCfg.rent, sourceContract.payment_method, durationHours,
        }
    )

    AH.Notify(targetServerId, ('Du har fået et lejetilbud (%s) fra %s. Åbn AgriHub for at svare.'):format(priceCfg.label, session.name), 'inform', 'Nyt lejetilbud')
    AH.LogAction('contracts', 'P2P_OFFER_CREATED', src, { contractId = contractId, machine = sourceContract.vehicle_model, target = targetXp.identifier })

    return { success = true, contractId = contractId, targetName = targetXp.getName() }
end)

-- Opsig et VERSERENDE (endnu ikke signeret) tilbud direkte ved at skrive
-- den anden parts server-ID — bruges som en robust fallback i NUI'en,
-- uafhængigt af om kontrakt-kortet rent faktisk er blevet renderet endnu.
lib.callback.register('masitz_agrihub:rental:p2p:cancelByPlayer', function(src, targetServerId)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Du er ikke logget ind på AgriHub.' } end

    local targetXp = AH.GetXPlayer(tonumber(targetServerId))
    if not targetXp then return { success = false, msg = 'Spilleren blev ikke fundet online. Tjek server-ID\'et.' } end

    local row = MySQL.single.await(
        [[SELECT contract_id FROM agrihub_contracts
          WHERE status = "pending"
            AND ((owner_identifier = ? AND renter_identifier = ?) OR (owner_identifier = ? AND renter_identifier = ?))
          ORDER BY created_at DESC LIMIT 1]],
        { session.identifier, targetXp.identifier, targetXp.identifier, session.identifier }
    )
    if not row then return { success = false, msg = 'Ingen verserende kontrakt fundet med denne spiller.' } end

    MySQL.update.await('UPDATE agrihub_contracts SET status = "cancelled" WHERE contract_id = ?', { row.contract_id })
    AH.LogAction('contracts', 'P2P_CANCELLED', src, { contractId = row.contract_id, target = targetXp.identifier })

    return { success = true, contractId = row.contract_id }
end)

lib.callback.register('masitz_agrihub:rental:p2p:respond', function(src, contractId, accept)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Du er ikke logget ind på AgriHub.' } end

    local contract = FindContract(contractId)
    if not contract or contract.status ~= 'pending' then
        return { success = false, msg = 'Dette tilbud findes ikke længere.' }
    end
    if contract.renter_identifier ~= session.identifier then
        return { success = false, msg = 'Dette tilbud er ikke til dig.' }
    end

    if not accept then
        MySQL.update.await('UPDATE agrihub_contracts SET status = "cancelled" WHERE contract_id = ?', { contractId })
        local ownerSrc = FindSrcByIdentifier(contract.owner_identifier)
        if ownerSrc then AH.Notify(ownerSrc, 'Dit lejetilbud blev afvist.', 'error') end
        return { success = true, accepted = false }
    end

    MySQL.update.await('UPDATE agrihub_contracts SET renter_approved = 1 WHERE contract_id = ?', { contractId })
    local ownerSrc = FindSrcByIdentifier(contract.owner_identifier)
    if ownerSrc then AH.Notify(ownerSrc, 'Dit lejetilbud blev godkendt — begge parter skal nu signere.', 'success') end

    return { success = true, accepted = true }
end)

lib.callback.register('masitz_agrihub:rental:p2p:sign', function(src, contractId)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Du er ikke logget ind på AgriHub.' } end

    local contract = FindContract(contractId)
    if not contract or contract.status ~= 'pending' then
        return { success = false, msg = 'Denne kontrakt kan ikke signeres.' }
    end

    local isOwner  = contract.owner_identifier == session.identifier
    local isRenter = contract.renter_identifier == session.identifier
    if not isOwner and not isRenter then
        return { success = false, msg = 'Denne kontrakt tilhører ikke dig.' }
    end
    if contract.owner_approved == 0 or contract.renter_approved == 0 then
        return { success = false, msg = 'Kontrakten skal godkendes af begge parter, før den kan signeres.' }
    end

    local column = isOwner and 'owner_signed' or 'renter_signed'
    MySQL.update.await(('UPDATE agrihub_contracts SET %s = 1 WHERE contract_id = ?'):format(column), { contractId })

    contract = FindContract(contractId)
    if contract.owner_signed == 0 or contract.renter_signed == 0 then
        return { success = true, activated = false }
    end

    -- Begge har signeret. To hurtige dobbelt-klik (eller en genafsendt
    -- NUI-request) kan begge nå hertil samtidig FØR nogen af dem har
    -- betalt — den atomiske UPDATE herunder sikrer at kun ÉT kald reelt
    -- vinder retten til at aktivere/opkræve (samme mønster som
    -- tasks:claim). Status flippes synkront, FØR den ventende betaling.
    local won = MySQL.update.await(
        'UPDATE agrihub_contracts SET status = "activating" WHERE contract_id = ? AND status = "pending"',
        { contractId }
    )
    if not won or won < 1 then
        return { success = true, activated = false }
    end

    -- Begge har signeret — aktivér kontrakten. Lejeren betaler NU,
    -- og nøglen skifter FØRST hånd her.
    local renterSrc = FindSrcByIdentifier(contract.renter_identifier)
    if not renterSrc then
        MySQL.update.await('UPDATE agrihub_contracts SET status = "pending" WHERE contract_id = ?', { contractId })
        return { success = false, msg = 'Lejeren er ikke længere online — signering annulleret.' }
    end

    local renterXp = AH.GetXPlayer(renterSrc)
    if not renterXp or not AH.TryCharge(renterXp, contract.payment_method, contract.deposit + contract.rent) then
        MySQL.update.await('UPDATE agrihub_contracts SET status = "pending" WHERE contract_id = ?', { contractId })
        return { success = false, msg = 'Lejeren har ikke råd — signering annulleret.' }
    end

    MySQL.update.await(
        [[UPDATE agrihub_contracts
          SET status = 'active', start_at = NOW(),
              expires_at = DATE_ADD(NOW(), INTERVAL TIMESTAMPDIFF(HOUR, start_at, expires_at) HOUR)
          WHERE contract_id = ?]],
        { contractId }
    )

    local ownerSrc = FindSrcByIdentifier(contract.owner_identifier)
    if ownerSrc then AH.RemoveKey(ownerSrc, contract.vehicle_plate) end
    AH.GiveKey(renterSrc, contract.vehicle_plate)
    AH.RegisterVehicle(contract.vehicle_plate, { src = renterSrc, type = 'rental', refId = contractId, model = contract.vehicle_model })

    if ownerSrc then AH.Notify(ownerSrc, 'Fremlejekontrakten er nu aktiv.', 'success') end
    AH.Notify(renterSrc, 'Fremlejekontrakten er nu aktiv — du har fået nøglen.', 'success')

    AH.LogAction('contracts', 'P2P_ACTIVATED', src, { contractId = contractId, plate = contract.vehicle_plate })

    return { success = true, activated = true }
end)

lib.callback.register('masitz_agrihub:rental:p2p:cancel', function(src, contractId)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Du er ikke logget ind på AgriHub.' } end

    local contract = FindContract(contractId)
    if not contract or contract.status ~= 'pending' then
        return { success = false, msg = 'Denne kontrakt kan ikke annulleres.' }
    end
    if contract.owner_identifier ~= session.identifier and contract.renter_identifier ~= session.identifier then
        return { success = false, msg = 'Denne kontrakt tilhører ikke dig.' }
    end

    -- Ingen penge er flyttet endnu (kun ved fuld signering) — ren annullering.
    MySQL.update.await('UPDATE agrihub_contracts SET status = "cancelled" WHERE contract_id = ?', { contractId })
    AH.LogAction('contracts', 'P2P_CANCELLED', src, { contractId = contractId })

    return { success = true }
end)

-- ─── CLEANUP VED DISCONNECT ──────────────────────────────────────
-- Ingen penge er bundet i en 'pending' kontrakt (kun ved fuld
-- signering), så disse kan trygt annulleres. Aktive kontrakter
-- rører vi IKKE — køretøjet består til spilleren reconnecter eller
-- kontrakten selv udløber (lazy expiry).
AH.RegisterCleanupHook(function(src)
    local xp = AH.GetXPlayer(src)
    if not xp then return end
    MySQL.update(
        'UPDATE agrihub_contracts SET status = "cancelled" WHERE status = "pending" AND (owner_identifier = ? OR renter_identifier = ?)',
        { xp.identifier, xp.identifier }
    )
end)

AH.Log('server/rental.lua indlæst.')
