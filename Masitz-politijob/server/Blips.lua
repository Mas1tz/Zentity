-- ============================================================
--  MM-PolitiJob – server/Blips.lua  v3
--  Live blips via StateBag sync - ingen polling delay til klienten
--
--  PERFORMANCE FIX: den gamle version kaldte SV.Framework.GetJob()
--  (og dermed SV.Framework.GetPlayer()) for HVER ENESTE online
--  spiller, hver eneste sekund, uanset job. På en fyldt server er
--  det unødvendigt konstant scanning. Nu vedligeholdes et lille sæt
--  af spillere med et relevant job (Config.AllowedJobs), som kun
--  opdateres når nogen rent faktisk skifter job, connecter eller
--  disconnecter - selve 1-sekunds-loopet opdaterer kun POSITIONEN
--  for de spillere der allerede er i sættet.
-- ============================================================

local trackedPlayers = {} -- [src] = true, hvis spilleren har et Config.AllowedJobs job

-- Opdater en spillers blip-data i deres statebag
-- Klienter lytter på statebag-changes → ingen fast timer
local function UpdatePlayerBlipState(src)
    local ped = GetPlayerPed(src)
    if not DoesEntityExist(ped) then return end

    local job = SV.Framework.GetJob(src)
    local coords = GetEntityCoords(ped)
    local veh    = GetVehiclePedIsIn(ped, false)
    local inVeh  = veh ~= 0

    -- vehicleType sættes server-side via entity model
    -- GetVehicleClass er client-only — brug model hash check i stedet
    local vehicleType = nil
    if inVeh then
        -- Klienten udleder sprite fra vehicleType
        -- Vi sender entity handle og klienten afgør klasse
        vehicleType = 'car'  -- default — klient overskriver via GetVehicleClass
    end

    Player(src).state:set('blipData', {
        job         = job,
        coords      = { x = coords.x, y = coords.y, z = coords.z },
        inVeh       = inVeh,
        vehicleType = vehicleType,
        name        = SV.Framework.GetName(src),
        active      = true,
    }, true)
end

local function ClearPlayerBlip(src)
    local p = Player(src)
    if p then p.state:set('blipData', nil, true) end
end

-- Genevaluér om en spiller hører til i det trackede sæt, og
-- opdater/ryd deres blip med det samme.
local function SyncTracking(src)
    local job = SV.Framework.GetJob(src)

    if job and Config.AllowedJobs[job] then
        trackedPlayers[src] = true
        UpdatePlayerBlipState(src)
    else
        if trackedPlayers[src] then
            trackedPlayers[src] = nil
            ClearPlayerBlip(src)
        end
    end
end

-- ── OPDATER POSITION FOR TRACKEDE SPILLERE ────────────────────
-- Kun de spillere der rent faktisk har et relevant job bliver
-- opdateret hvert sekund - ikke hele spillerlisten.
CreateThread(function()
    while true do
        Wait(1000)
        for src, _ in pairs(trackedPlayers) do
            if GetPlayerName(src) then
                UpdatePlayerBlipState(src)
            else
                -- Spilleren er væk uden at playerDropped nåede at fyre endnu
                trackedPlayers[src] = nil
            end
        end
    end
end)

-- ── RESOURCE (RE)START: find allerede-tilsluttede relevante spillere ──
CreateThread(function()
    Wait(2000) -- vent på at framework/spillerdata er klar
    for _, pid in ipairs(GetPlayers()) do
        SyncTracking(tonumber(pid))
    end
end)

-- Ryd blip + tracking ved disconnect
AddEventHandler('playerDropped', function()
    local src = source
    trackedPlayers[src] = nil
    ClearPlayerBlip(src)
end)

-- Opdater ved job-skift (ESX / QB trigger disse lokalt server-side,
-- så almindelig AddEventHandler er korrekt her - det er IKKE
-- networked client->server events)
AddEventHandler('esx:setJob', function(src)
    Wait(500)
    SyncTracking(src)
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(src)
    Wait(500)
    SyncTracking(src)
end)

-- Login: fang spillere der allerede har et relevant job ved login
AddEventHandler('esx:playerLoaded', function(src)
    Wait(500)
    SyncTracking(src)
end)

AddEventHandler('QBCore:Server:OnPlayerLoaded', function(src)
    Wait(500)
    SyncTracking(src)
end)
