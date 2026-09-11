-- ============================================================
--  Masitz-AgriHub | client/vehicles.lua
--  Delte hjælpefunktioner til at spawne/slette AgriHub-køretøjer og
--  koble trailere på — bruges af både client/tasks.lua og
--  client/rental.lua så logikken kun findes ét sted.
-- ============================================================

AH = AH or {}

-- lib.requestModel FEJLER med error() (ikke et falsy return) hvis modellen
-- er ugyldig eller timer ud — en enkelt forkert model-streng i config.lua
-- ville ellers stoppe HELE spawn-flowet uden nogen synlig fejl for
-- spilleren. pcall'et her sikrer at vi altid får et roligt nil tilbage
-- i stedet, og kan give spilleren en rigtig besked.
local function SafeRequestModel(hash)
    local ok, err = pcall(lib.requestModel, hash, 10000)
    if not ok then
        print(('[Masitz-AgriHub] Kunne ikke loade model %s: %s'):format(tostring(hash), tostring(err)))
        return false
    end
    return true
end

-- Spawner et køretøj med en given plade og returnerer entity-handlet.
-- Kaldes KUN efter serveren allerede har godkendt/registreret pladen
-- (se server/vehicles.lua/rental.lua/tasks.lua) — clienten opfinder
-- aldrig selv en plade.
function AH.SpawnVehicle(model, coords, heading, plate)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    if not SafeRequestModel(hash) then return nil end

    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)

    if not DoesEntityExist(veh) then return nil end

    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleNumberPlateText(veh, plate)
    SetVehicleFuelLevel(veh, 100.0)
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleOnGroundProperly(veh)

    -- Burrito må kun bruges med bestemte liveries (§ config) — tildel
    -- en tilladt livery med det samme frem for at lade spilleren vælge
    -- en ikke-tilladt en bagefter.
    if type(model) == 'string' and model:lower():find('^burrito') then
        local allowed = Config.Agri.VehicleLiveries.burrito
        if allowed and #allowed > 0 then
            SetVehicleLivery(veh, allowed[math.random(1, #allowed)])
        end
    end

    return veh
end

-- Kobler en trailer-model på et allerede-spawnet trækkøretøj og
-- returnerer trailer-entityen.
function AH.AttachTrailer(vehicle, trailerModel, coords, heading)
    local hash = type(trailerModel) == 'string' and GetHashKey(trailerModel) or trailerModel
    if not SafeRequestModel(hash) then return nil end

    local trailer = CreateVehicle(hash, coords.x, coords.y, coords.z, heading or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(trailer) then return nil end

    SetEntityAsMissionEntity(trailer, true, true)
    AttachVehicleToTrailer(vehicle, trailer, 5.0)

    return trailer
end

-- Sikker sletning: kun hvis entityen rent faktisk er et køretøj, og
-- ingen spiller sidder i det.
function AH.DeleteVehicleSafe(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if GetPedInVehicleSeat(veh, -1) ~= 0 then return end

    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)
end

RegisterNetEvent('masitz_agrihub:rental:deleteVehicle', function(netId)
    -- Serveren sender et net-ID, ikke et entity-handle — server- og
    -- client-side handles er forskellige tal for samme entity.
    CreateThread(function()
        local attempts = 0
        while not NetworkDoesNetworkIdExist(netId) and attempts < 20 do
            Wait(100)
            attempts = attempts + 1
        end
        if not NetworkDoesNetworkIdExist(netId) then return end

        local veh = NetworkGetEntityFromNetworkId(netId)

        -- Serveren har lige godkendt afleveringen for DENNE spiller — de
        -- sidder pr. definition i køretøjet i det øjeblik, så vi venter
        -- til de stiger ud, i stedet for at forsøge en tvangssletning imens.
        attempts = 0
        while DoesEntityExist(veh) and GetPedInVehicleSeat(veh, -1) ~= 0 and attempts < 100 do
            Wait(500)
            attempts = attempts + 1
        end
        AH.DeleteVehicleSafe(veh)
    end)
end)
