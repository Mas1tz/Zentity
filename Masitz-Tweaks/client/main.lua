-- ============================================================
--  Masitz-Tweaks | client/main.lua
--
--  Samlet, performance-optimeret erstatning for 4 separate
--  scripts: disableDispatch, noemergencycars, removeAIcops,
--  disable_radio.
--
--  ROOT-CAUSE-analyse af de gamle CPU-tal (se README for fuld
--  gennemgang):
--    - disableDispatch (~3.20 ms): kaldte EnableDispatchService
--      (12x) + 3 wanted-level-natives HVER FRAME. EnableDispatchService
--      er IKKE en "ThisFrame"-native — den er persistent og skal kun
--      sættes én gang. Wanted-level skal reapplyes periodisk, men
--      IKKE 60x/sekund.
--    - removeAIcops (~1.60 ms): kaldte ClearAreaOfCops (400m radius —
--      en af GTA's tungeste population-natives) HVER FRAME, i stedet
--      for at forhindre spawn med de lette, persistente
--      SetCreateRandomCops-natives.
--    - noemergencycars (~1.20 ms): PlayerData blev ALDRIG udfyldt
--      (intet esx:setJob-handler fandtes), så blokken kørte reelt
--      aldrig — de 1.20 ms blev brugt på at polle IsPedInAnyPoliceVehicle
--      hver frame for ingenting. Betingelsen havde desuden en
--      De Morgan-logikfejl (`or` i stedet for `and`) der ville have
--      gjort den forkert selv hvis den havde virket.
--    - disable_radio (~0.00 ms): allerede optimalt — Wait(1000),
--      ingen tunge natives. Uændret her, kun frigjort fra en ubrugt
--      ESX-reference.
-- ============================================================

local function DebugPrint(fmt, ...)
    if Config.Debug then
        print(('[Masitz-Tweaks] ' .. fmt):format(...))
    end
end

-- ════════════════════════════════════════════════════════════
--  1) DISPATCH (erstatter disableDispatch)
--  EnableDispatchService er persistent — sættes ÉN gang.
--  Kun wanted-level skal reapplyes periodisk (andre resources/
--  events kan hæve den), men i et roligt tempo, ikke hver frame.
-- ════════════════════════════════════════════════════════════

local function ApplyDispatchSettings()
    for i = 1, Config.DispatchServiceCount do
        EnableDispatchService(i, false)
    end
    DebugPrint('Dispatch services 1-%d deaktiveret (one-time, persistent).', Config.DispatchServiceCount)
end

if Config.DisableDispatch then
    CreateThread(function()
        while true do
            Wait(Config.WantedLevelInterval)
            local playerId = PlayerId()
            SetPlayerWantedLevel(playerId, 0, false)
            SetPlayerWantedLevelNow(playerId, false)
            SetPlayerWantedLevelNoDrop(playerId, 0, false)
        end
    end)
end

-- ════════════════════════════════════════════════════════════
--  2) AI COPS (erstatter removeAIcops)
--  SetCreateRandomCops-familien er persistent — sættes ÉN gang.
--  AICopsSafetyInterval er et billigt sikkerhedsnet: reapplicerer
--  flagene (i tilfælde af at et andet resource nulstiller dem) og
--  laver ÉN ClearAreaOfCops-sweep for at fange scriptede cop-peds
--  der er spawnet direkte (uden om population-systemet, som
--  SetCreateRandomCops ikke har nogen kontrol over). Sæt
--  Config.AICopsSafetyInterval = 0 for at slå denne sweep helt fra.
-- ════════════════════════════════════════════════════════════

local function ApplyAICopSettings()
    SetCreateRandomCops(false)
    SetCreateRandomCopsNotOnScenarios(false)
    SetCreateRandomCopsOnScenarios(false)
    DebugPrint('AI cop population-flags deaktiveret (persistent).')
end

if Config.DisableAICops and Config.AICopsSafetyInterval > 0 then
    CreateThread(function()
        while true do
            Wait(Config.AICopsSafetyInterval)
            ApplyAICopSettings()

            local ped = PlayerPedId()
            if DoesEntityExist(ped) then
                local coords = GetEntityCoords(ped)
                ClearAreaOfCops(coords.x, coords.y, coords.z, Config.AICopsClearRadius)
                DebugPrint('AI cops sikkerheds-sweep kørt (radius %.0fm).', Config.AICopsClearRadius)
            end
        end
    end)
end

-- ════════════════════════════════════════════════════════════
--  3) AMBIENT EMERGENCY-TRAFIK (§7 — "noemergencycars", del 1)
--  GTA har INGEN native der permanent undertrykker én bestemt
--  køretøjsklasse fra ambient population-spawn — det er derfor
--  IKKE muligt at nå ~0.00 ms for denne specifikke funktion uden
--  at funktionen reelt stopper med at virke (se §21 i din
--  specifikation). Dette ER den billigste korrekte løsning: én
--  scan hvert Config.EmergencyTrafficSweepInterval (standard 5s,
--  ikke hver frame), der aldrig rører et køretøj nogen spiller
--  sidder i.
-- ════════════════════════════════════════════════════════════

local function IsVehicleOccupiedByAnyPlayer(veh)
    local maxSeat = GetVehicleMaxNumberOfPassengers(veh)
    for seat = -1, maxSeat do
        local occupant = GetPedInVehicleSeat(veh, seat)
        if occupant ~= 0 and IsPedAPlayer(occupant) then
            return true
        end
    end
    return false
end

if Config.DisableEmergencyTraffic then
    CreateThread(function()
        while true do
            Wait(Config.EmergencyTrafficSweepInterval)

            local vehicles = GetGamePool('CVehicle')
            local cleared = 0
            for i = 1, #vehicles do
                local veh = vehicles[i]
                if DoesEntityExist(veh) and GetVehicleClass(veh) == Config.EmergencyVehicleClass
                   and not IsVehicleOccupiedByAnyPlayer(veh) then
                    -- Ikke force-delete: vi har ikke nødvendigvis network-
                    -- ownership, og et forceret DeleteEntity på et køretøj en
                    -- anden klient ejer kan desynce. SetEntityAsNoLongerNeeded
                    -- er den sikre, ikke-destruktive måde at bede population-
                    -- systemet om at rydde det op på.
                    SetEntityAsNoLongerNeeded(veh)
                    cleared = cleared + 1
                end
            end
            if cleared > 0 then
                DebugPrint('Ambient emergency-trafik sweep: %d køretøj(er) markeret no-longer-needed.', cleared)
            end
        end
    end)
end

-- ════════════════════════════════════════════════════════════
--  4) FØRSTE-RESPONDENT KØRSELS-SPÆRRE (§7 — "noemergencycars", del 2)
--  Den oprindelige, tiltænkte adfærd bag "noemergencycars": kun
--  police/ambulance-job må FØRE et emergency-køretøj. Genopbygget
--  fra bunden, 100% event-drevet (CEventNetworkPlayerEnteredVehicle)
--  i stedet for det oprindelige Wait(0)-loop — nul polling-cost.
--  Kræver ESX (eneste feature i denne resource der gør, ligesom det
--  oprindelige script).
-- ════════════════════════════════════════════════════════════

local ESX = nil
local PlayerData = { job = nil }

if Config.RestrictEmergencyVehicles then
    CreateThread(function()
        while GetResourceState('es_extended') ~= 'started' do
            Wait(500)
        end
        ESX = exports['es_extended']:getSharedObject()
        PlayerData = ESX.GetPlayerData()

        RegisterNetEvent('esx:setJob', function(job)
            PlayerData.job = job
        end)
        RegisterNetEvent('esx:playerLoaded', function(xPlayer)
            PlayerData.job = xPlayer.job
        end)

        DebugPrint('ESX fundet — første-respondent kørsels-spærre er aktiv.')
    end)

    AddEventHandler('gameEventTriggered', function(eventName, args)
        if eventName ~= 'CEventNetworkPlayerEnteredVehicle' then return end

        local ped, veh = args[1], args[2]
        if ped ~= PlayerPedId() then return end
        if not DoesEntityExist(veh) then return end
        if GetPedInVehicleSeat(veh, -1) ~= ped then return end -- kun føreren
        if GetVehicleClass(veh) ~= Config.EmergencyVehicleClass then return end

        local jobName = PlayerData.job and PlayerData.job.name
        if not jobName or not Config.AllowedEmergencyJobs[jobName] then
            SetVehicleUndriveable(veh, true)
            if ESX then
                ESX.ShowNotification('Emergency-køretøjer er kun til førstehjælpere.')
            end
            DebugPrint('Spiller uden godkendt job forsøgte at føre et emergency-køretøj (job=%s).', tostring(jobName))
        end
    end)
end

-- ════════════════════════════════════════════════════════════
--  5) RADIO (erstatter disable_radio)
--  Allerede optimal i det oprindelige script (~0.00 ms) — UÆNDRET
--  logik/interval. Kun den ubrugte ESX/PlayerData-reference (blev
--  aldrig læst i det oprindelige script) er fjernet.
-- ════════════════════════════════════════════════════════════

if Config.DisableRadio then
    CreateThread(function()
        while true do
            Wait(Config.RadioCheckInterval)
            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false) then
                SetUserRadioControlEnabled(false)
                if GetPlayerRadioStationName() ~= nil then
                    SetVehRadioStation(GetVehiclePedIsIn(ped, false), 'OFF')
                end
            end
        end
    end)
end

-- ════════════════════════════════════════════════════════════
--  STATISKE SETTINGS — sættes ÉN gang ved resource-load, og
--  reapplyes defensivt ved hvert spawn (billigt: sker kun ved
--  spawn, ikke i en loop).
-- ════════════════════════════════════════════════════════════

if Config.DisableDispatch then ApplyDispatchSettings() end
if Config.DisableAICops then ApplyAICopSettings() end

AddEventHandler('playerSpawned', function()
    if Config.DisableDispatch then ApplyDispatchSettings() end
    if Config.DisableAICops then
        ApplyAICopSettings()
        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            local coords = GetEntityCoords(ped)
            ClearAreaOfCops(coords.x, coords.y, coords.z, Config.AICopsClearRadius)
        end
    end
end)

DebugPrint('Masitz-Tweaks indlæst.')
