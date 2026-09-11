-- ============================================================
--  Masitz-garage | server/sv_transfer.lua
--  Flyt bil mellem garager (§14) + "Hent bil hertil" ved tom
--  garage (§15). Samme server-funktion (ExecuteTransfer) bruges
--  af begge UI-indgange for at undgå duplikeret logik (§30).
--
--  Prisen beregnes og genberegnes ALTID server-side — klienten
--  ser kun et estimat (fra getTransferOptions), aldrig noget der
--  reelt bestemmer beløbet der trækkes (§15/§16).
-- ============================================================

-- ─── PRISBEREGNING (§15) ────────────────────────────────────────
function MG.CalcTransferPrice(fromKey, toKey)
    local a, b = Config.Garages[fromKey], Config.Garages[toKey]
    if not a or not b then return Config.GarageTransfer.minPrice end

    local distKm = MG.GarageDistance(a, b) / 1000.0
    local price  = Config.GarageTransfer.minPrice + (distKm * Config.GarageTransfer.pricePerKm)
    price = math.max(Config.GarageTransfer.minPrice, math.min(Config.GarageTransfer.maxPrice, price))
    return math.floor(price + 0.5)
end

-- ─── "FLYT BIL": alle gyldige destinationer + estimeret pris ──────
lib.callback.register('masitz_garage:getTransferOptions', function(src, plate)
    local xp = MG.GetXPlayer(src)
    if not xp then return {} end

    plate = MG.NormPlate(plate)
    if not plate then return {} end

    local row = MySQL.single.await(
        [[SELECT parking, garage_type FROM owned_vehicles
          WHERE  owner = ? AND REPLACE(plate," ","") = ? AND impound = 0 AND stored = 1]],
        { xp.identifier, plate }
    )
    if not row then return {} end

    local options = {}
    for key, cfg in pairs(Config.Garages) do
        if cfg.type == row.garage_type and key ~= row.parking then
            options[#options + 1] = { key = key, label = cfg.label or key, price = MG.CalcTransferPrice(row.parking, key) }
        end
    end
    table.sort(options, function(a, b) return a.price < b.price end)
    return options
end)

-- ─── "HENT BIL HERTIL": spillerens ØVRIGE biler + pris til HER ────
lib.callback.register('masitz_garage:getOtherStoredVehicles', function(src, garageKey)
    local xp = MG.GetXPlayer(src)
    if not xp then return {} end

    garageKey = tostring(garageKey or '')
    local destCfg = Config.Garages[garageKey]
    if not destCfg then return {} end

    local vehicles = MG.GetOtherStoredVehicles(xp.identifier, destCfg.type, garageKey)
    for _, v in ipairs(vehicles) do
        v.price = MG.CalcTransferPrice(v.parking, garageKey)
    end
    table.sort(vehicles, function(a, b) return a.price < b.price end)
    return vehicles
end)

-- ─── UDFØR FLYTNINGEN (delt af begge UI-flows) ────────────────────
lib.callback.register('masitz_garage:executeTransfer', function(src, plate, destinationKey)
    local xp = MG.GetXPlayer(src)
    if not xp then return { success = false, msg = 'Ikke logget ind.' } end

    plate = MG.NormPlate(plate)
    destinationKey = tostring(destinationKey or '')

    if not plate then return { success = false, msg = 'Ugyldig nummerplade.' } end
    local destCfg = Config.Garages[destinationKey]
    if not destCfg then return { success = false, msg = 'Ugyldig destinationsgarage.' } end

    local row = MySQL.single.await(
        [[SELECT parking, garage_type, stored, impound FROM owned_vehicles
          WHERE  owner = ? AND REPLACE(plate," ","") = ?]],
        { xp.identifier, plate }
    )
    if not row then return { success = false, msg = 'Du ejer ikke dette køretøj.' } end
    if row.impound == 1 then return { success = false, msg = 'Bilen er på impound.' } end
    if row.stored ~= 1 then return { success = false, msg = 'Bilen skal være parkeret for at kunne flyttes.' } end
    if destCfg.type ~= row.garage_type then return { success = false, msg = 'Denne garage passer ikke til køretøjstypen.' } end
    if row.parking == destinationKey then return { success = false, msg = 'Bilen står allerede i denne garage.' } end

    -- Prisen genberegnes HER, uafhængigt af hvad klienten viste tidligere.
    local price = MG.CalcTransferPrice(row.parking, destinationKey)
    local account = Config.GarageTransfer.paymentAccount or 'bank'

    if not MG.TryCharge(xp, account, price) then
        return { success = false, msg = ('Du har ikke råd (%s fra %s).'):format(MG.FormatMoney(price), account == 'bank' and 'bank' or 'kontanter') }
    end

    local changed = MySQL.update.await(
        [[UPDATE owned_vehicles
          SET    parking = ?, last_garage = ?
          WHERE  owner = ? AND REPLACE(plate," ","") = ? AND impound = 0 AND stored = 1]],
        { destinationKey, destinationKey, xp.identifier, plate }
    )

    if not changed or changed < 1 then
        MG.Pay(xp, account, price)
        return { success = false, msg = 'Database-fejl — pengene er refunderet.' }
    end

    MG.LogGarageTransfer({
        playerName = xp.getName(), identifier = xp.identifier,
        plate = plate, fromLabel = (Config.Garages[row.parking] and Config.Garages[row.parking].label) or row.parking,
        toLabel = destCfg.label, price = price,
    })
    MG.Log(('TRANSFER: %s flyttede %s fra %s til %s for %d kr.'):format(xp.identifier, plate, row.parking, destinationKey, price))

    return { success = true, price = price, toLabel = destCfg.label }
end)
