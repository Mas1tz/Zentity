-- ============================================================
--  Masitz-AgriHub | client/rental.lua
--  Maskinudlejning-klient: spawn af lejede maskiner, afleverings-
--  zone (ox_target, ikke en distance-loop), og fremleje-dialoger
--  (spiller-opslag + navn-bekræftelse) der bridger til
--  server/rental.lua's kontrakt-callbacks.
-- ============================================================

AH = AH or {}
AH.ActiveRental = nil -- { contractId, plate, model, vehicle }

function AH.NormPlate(plate)
    if not plate then return nil end
    return tostring(plate):gsub('%s+', ''):upper()
end

-- ─── LEJ FRA AGRIHUB ─────────────────────────────────────────────
-- Kaldes fra client/nui.lua's RegisterNUICallback for 'rental:npcCreate'.
function AH.StartNpcRental(machine, paymentMethod, durationHours)
    local result = lib.callback.await('masitz_agrihub:rental:npc:create', false, machine, paymentMethod, durationHours)
    if not result or not result.success then
        return { success = false, msg = result and result.msg or 'Kunne ikke oprette lejeaftale.' }
    end

    local coords = result.spawnCoords
    local veh = AH.SpawnVehicle(result.model, coords, coords.w or 0.0, result.plate)
    if not veh then
        return { success = false, msg = 'Køretøjet kunne ikke spawnes.' }
    end

    TriggerServerEvent('masitz_agrihub:rental:vehicleSpawned', result.plate)

    AH.ActiveRental = { contractId = result.contractId, plate = result.plate, model = result.model, vehicle = veh }

    lib.notify({ title = 'AgriHub Udlejning', description = ('%s er klar — kør til afleveringszonen når du er færdig.'):format(result.model), type = 'success' })
    return { success = true, contractId = result.contractId }
end

-- ─── AFLEVERINGSZONE (§35, event-drevet, ingen loop) ────────────
CreateThread(function()
    local zone = Config.Agri.RentalReturnZone
    exports.ox_target:addBoxZone({
        coords = zone.coords,
        size = vec3(zone.distance * 2, zone.distance * 2, 3.0),
        debug = Config.Agri.Debug,
        options = {
            {
                name = 'masitz_agrihub_rental_return',
                icon = 'fa-solid fa-warehouse',
                label = 'Aflever lejet køretøj',
                canInteract = function()
                    local ped = PlayerPedId()
                    return GetVehiclePedIsIn(ped, false) ~= 0
                end,
                onSelect = function()
                    local ped = PlayerPedId()
                    local veh = GetVehiclePedIsIn(ped, false)
                    if veh == 0 then return end
                    local plate = AH.NormPlate(GetVehicleNumberPlateText(veh))

                    local result = lib.callback.await('masitz_agrihub:rental:return', false, plate)
                    if result and result.success then
                        lib.notify({ title = 'AgriHub Udlejning', description = ('Køretøj afleveret — %d kr. i depositum refunderet.'):format(result.depositRefunded), type = 'success' })
                        if AH.ActiveRental and AH.ActiveRental.plate == plate then
                            AH.ActiveRental = nil
                        end
                    else
                        lib.notify({ title = 'AgriHub Udlejning', description = result and result.msg or 'Kunne ikke aflevere køretøjet.', type = 'error' })
                    end
                end,
            },
        },
    })
end)

AH.NormPlate = AH.NormPlate or function(plate)
    if not plate then return nil end
    plate = tostring(plate):gsub('%s+', ''):upper()
    return plate
end

-- ─── FREMLEJE: SPILLER-OPSLAG + NAVN-BEKRÆFTELSE (§28, §31-§33) ──
-- Bruges af NUI'ens Kontrakter-fane til at slå en modtager op og
-- lade spilleren bekræfte navnet, før tilbuddet sendes til serveren.
function AH.LookupRentalPlayer(query)
    return lib.callback.await('masitz_agrihub:rental:p2p:lookupPlayer', false, query) or {}
end

function AH.OfferSublet(sourceContractId, targetServerId, targetName)
    local confirmed = lib.alertDialog({
        header = 'Bekræft fremleje',
        content = ('Tilbyd denne lejekontrakt til %s (ID %d)?'):format(targetName, targetServerId),
        centered = true,
        cancel = true,
    })
    if confirmed ~= 'confirm' then return { success = false, msg = 'Annulleret.' } end

    local result = lib.callback.await('masitz_agrihub:rental:p2p:create', false, sourceContractId, targetServerId)
    if result and result.success then
        lib.notify({ title = 'AgriHub Udlejning', description = 'Tilbud sendt — venter på modtagerens svar.', type = 'inform' })
    end
    return result or { success = false, msg = 'Ingen forbindelse til serveren.' }
end

function AH.RespondToSublet(contractId, accept)
    return lib.callback.await('masitz_agrihub:rental:p2p:respond', false, contractId, accept)
end

function AH.SignContract(contractId)
    return lib.callback.await('masitz_agrihub:rental:p2p:sign', false, contractId)
end

function AH.CancelSublet(contractId)
    return lib.callback.await('masitz_agrihub:rental:p2p:cancel', false, contractId)
end

function AH.ExtendRental(contractId, extraHours)
    return lib.callback.await('masitz_agrihub:rental:extend', false, contractId, extraHours)
end

function AH.GetRentalCatalog()
    return lib.callback.await('masitz_agrihub:rental:catalog', false) or { machines = {}, rules = {} }
end

function AH.GetRentalList()
    return lib.callback.await('masitz_agrihub:rental:list', false) or { asRenter = {}, asOwner = {} }
end
