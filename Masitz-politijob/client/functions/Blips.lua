-- ============================================================
--  MM-PolitiJob – client/functions/Blips.lua  v2
--  StateBag-baserede live blips — ingen polling delay
--  Korrekte sprites: til fods, bil, motorcykel, båd, helikopter
--  Farve: blå for alle (farve 3 = blå i GTA)
-- ============================================================

local activeBlips  = {}   -- [serverId] = blip handle
local stateWatchers = {}  -- [serverId] = watcher handle

-- ── SPRITE HELPER ────────────────────────────────────────────
-- Bestemmer korrekt sprite baseret på køretøjsklasse
local function GetVehicleSprite(jobCfg, entity)
    if not entity or entity == 0 then
        return jobCfg.sprites.default
    end

    local class = GetVehicleClass(entity)

    if class == 8  then return jobCfg.sprites.motorcycle or jobCfg.sprites.default end
    if class == 14 then return jobCfg.sprites.boat       or jobCfg.sprites.default end
    if class == 15 then return jobCfg.sprites.helicopter or jobCfg.sprites.default end
    -- Alle andre køretøjer = bil
    return jobCfg.sprites.car or jobCfg.sprites.default
end

-- ── OPRET ELLER OPDATER BLIP ─────────────────────────────────
local function UpsertBlip(sid, data)
    local myJob    = MM.State.jobName
    local myJobCfg = myJob and Config.AllowedJobs[myJob]
    if not myJobCfg then return end

    local jobCfg = Config.AllowedJobs[data.job]
    if not jobCfg then return end

    -- Tjek om vi må se dette job
    if not myJobCfg.canSee[data.job] then
        -- Fjern hvis vi ikke må se det
        if activeBlips[sid] and DoesBlipExist(activeBlips[sid]) then
            RemoveBlip(activeBlips[sid])
            activeBlips[sid] = nil
        end
        return
    end

    local c = data.coords

    -- Sprite: find køretøjet hvis spilleren er i et
    local sprite = jobCfg.sprites.default
    if data.inVeh then
        -- Find spillerens entity og afgør klasse lokalt
        local targetPed = GetPlayerPed(GetPlayerFromServerId(sid))
        local veh = GetVehiclePedIsIn(targetPed, false)
        sprite = GetVehicleSprite(jobCfg, veh)
    end

    if not activeBlips[sid] or not DoesBlipExist(activeBlips[sid]) then
        -- Opret nyt blip
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, sprite)
        SetBlipColour(blip, 3)          -- blå
        SetBlipScale(blip, 0.8)
        SetBlipAsShortRange(blip, false) -- altid synlig på kortet
        SetBlipDisplay(blip, 2)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(data.name or '–')
        EndTextCommandSetBlipName(blip)
        activeBlips[sid] = blip
    else
        -- Opdater eksisterende
        local blip = activeBlips[sid]
        SetBlipCoords(blip, c.x, c.y, c.z)
        SetBlipSprite(blip, sprite)
        SetBlipColour(blip, 3)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(data.name or '–')
        EndTextCommandSetBlipName(blip)
    end
end

-- ── FJERN BLIP FOR SPILLER ───────────────────────────────────
local function RemovePlayerBlip(sid)
    if activeBlips[sid] and DoesBlipExist(activeBlips[sid]) then
        RemoveBlip(activeBlips[sid])
    end
    activeBlips[sid] = nil
end

-- ── WATCH SPILLER ────────────────────────────────────────────
-- Lytter på statebag-ændringer for én spiller
local function WatchPlayer(pid, sid)
    if stateWatchers[sid] then return end

    stateWatchers[sid] = AddStateBagChangeHandler(
        'blipData',
        ('player:%d'):format(sid),
        function(_, _, value)
            if not value or not value.active then
                RemovePlayerBlip(sid)
            else
                UpsertBlip(sid, value)
            end
        end
    )
end

local function UnwatchPlayer(sid)
    if stateWatchers[sid] then
        RemoveStateBagChangeHandler(stateWatchers[sid])
        stateWatchers[sid] = nil
    end
    RemovePlayerBlip(sid)
end

-- ── INIT: Watch alle nuværende spillere ──────────────────────
local function InitWatchers()
    for _, pid in ipairs(GetActivePlayers()) do
        local sid = GetPlayerServerId(pid)
        WatchPlayer(pid, sid)

        -- Hent eksisterende statebag hvis allerede sat
        local data = Player(pid).state.blipData
        if data and data.active then
            UpsertBlip(sid, data)
        end
    end
end

-- ── SPILLER JOIN/LEAVE ────────────────────────────────────────
AddEventHandler('playerActivated', function()
    -- Vent et frame så spillerens state er klar
    Wait(500)
    for _, pid in ipairs(GetActivePlayers()) do
        local sid = GetPlayerServerId(pid)
        if not stateWatchers[sid] then
            WatchPlayer(pid, sid)
            local data = Player(pid).state.blipData
            if data and data.active then
                UpsertBlip(sid, data)
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    -- Lokalt event — vi ved ikke direkte hvem der droppede
    -- Cleanup håndteres via statebag → nil fra server
end)

-- ── JOB SKIFT → GEN-INIT ─────────────────────────────────────
-- Lytter på det centrale lokale event fra state.lua i stedet for at
-- registrere sine egne esx:setJob / QBCore:Client:OnJobUpdate handlers
-- (undgår duplicate handlers og holder job-logik ét sted).
AddEventHandler('mm:policeStatusChanged', function()
    -- Ryd alle og re-evaluer hvad vi må se
    for sid, _ in pairs(activeBlips) do
        RemovePlayerBlip(sid)
    end
    InitWatchers()
end)

-- ── CLEANUP ──────────────────────────────────────────────────
local function ClearAll()
    for sid, _ in pairs(stateWatchers) do
        RemoveStateBagChangeHandler(stateWatchers[sid])
    end
    stateWatchers = {}
    for sid, blip in pairs(activeBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    activeBlips = {}
end

AddEventHandler('onClientResourceStop', function(res)
    if res == GetCurrentResourceName() then ClearAll() end
end)

-- ── START ────────────────────────────────────────────────────
CreateThread(function()
    while not MM.State do Wait(100) end
    Wait(1000)
    InitWatchers()
end)