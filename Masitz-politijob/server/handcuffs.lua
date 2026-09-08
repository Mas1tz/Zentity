-- ============================================================
--  MM-PolitiJob – server/handcuffs.lua  v2
--  KRITISK FIX: ValidateAction manglede return true + end
--  RegisterNetEvent var defineret INDE I ValidateAction
--  → ingen events registreret → håndjern virkede 0%
-- ============================================================

local MAX_DIST = Config.HandcuffMaxDistance or 3.0

-- ── ANTI-SPAM ────────────────────────────────────────────────
local lastAction = {} -- [src] = GetGameTimer() ved sidste handcuff/escort trigger
local ACTION_COOLDOWN = 500 -- ms

local function IsRateLimited(src)
    local now = GetGameTimer()
    if lastAction[src] and (now - lastAction[src]) < ACTION_COOLDOWN then
        return true
    end
    lastAction[src] = now
    return false
end

local function GetPedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or not DoesEntityExist(ped) then return nil end
    return GetEntityCoords(ped)
end

local function ValidateDistance(src, targetId, maxDist)
    local c1 = GetPedCoords(src)
    local c2 = GetPedCoords(targetId)
    if not c1 or not c2 then return false end
    return #(c1 - c2) <= (maxDist or MAX_DIST)
end

-- FIX 1: Tilføjet return true + end der LUKKER funktionen korrekt
-- Original: RegisterNetEvent var indeni ValidateAction → aldrig global
local function ValidateAction(src, targetId)
    if tonumber(src) == tonumber(targetId) then
        return false, 'Kan ikke bruges på sig selv.'
    end
    if not SV.Framework.IsPolice(src) then
        return false, 'Kun politibetjente.'
    end
    if not GetPlayerName(targetId) then
        return false, 'Spiller ikke online.'
    end
    if not ValidateDistance(src, targetId, MAX_DIST) then
        return false, 'For langt væk.'
    end
    local tState = Player(targetId).state
    if tState and tState.isDead then
        return false, 'Spilleren er død.'
    end
    return true  -- ← KRITISK: manglede fuldstændigt
end             -- ← KRITISK: lukkede aldrig ValidateAction

-- ── HÅNDJERN ─────────────────────────────────────────────────
RegisterNetEvent('mm_police:server:handcuff', function(targetId, mode)
    local src = source
    targetId  = tonumber(targetId)
    if not targetId then return end
    if IsRateLimited(src) then return end

    -- Validér mode-parameteren eksplicit - klienten kan i princippet
    -- sende et vilkårligt argument.
    if mode ~= nil and mode ~= 'soft' and mode ~= 'hard' then return end

    local ok, err = ValidateAction(src, targetId)
    if not ok then
        SV_Notify(src, 'Fejl', err, 'error')
        return
    end

    local tState      = Player(targetId).state
    local isCuffed    = tState.isHandcuffed or false
    local currentMode = tState.handcuffMode

    if mode == nil then
        if not isCuffed then return end
        Player(targetId).state:set('isHandcuffed', false, true)
        Player(targetId).state:set('handcuffMode',  nil,  true)
        Player(targetId).state:set('isEscorted',  false,  true)
        Player(targetId).state:set('escortedBy',    nil,  true)
        TriggerClientEvent('mm_police:client:handcuff', targetId, false, nil)

    elseif mode == 'soft' then
        if isCuffed then return end
        Player(targetId).state:set('isHandcuffed', true,   true)
        Player(targetId).state:set('handcuffMode', 'soft', true)
        TriggerClientEvent('mm_police:client:handcuff', targetId, true, 'soft')

    elseif mode == 'hard' then
        if not isCuffed then return end
        if currentMode == 'hard' then return end
        Player(targetId).state:set('handcuffMode', 'hard', true)
        TriggerClientEvent('mm_police:client:handcuff', targetId, true, 'hard')
    end
end)

-- ── ESKORT ───────────────────────────────────────────────────
RegisterNetEvent('mm_police:server:escort', function(targetId, state)
    local src = source
    targetId  = tonumber(targetId)
    if not targetId then return end
    if IsRateLimited(src) then return end

    local ok, err = ValidateAction(src, targetId)
    if not ok then
        SV_Notify(src, 'Fejl', err, 'error')
        return
    end

    local tState = Player(targetId).state
    if state and not tState.isHandcuffed then
        SV_Notify(src, 'Fejl', 'Spilleren er ikke håndjernet.', 'error')
        return
    end
    if state and tState.isEscorted then
        SV_Notify(src, 'Fejl', 'Spilleren eskorteres allerede.', 'error')
        return
    end

    Player(targetId).state:set('isEscorted', state,          true)
    Player(targetId).state:set('escortedBy', state and src or nil, true)
    TriggerClientEvent('mm_police:client:escort', targetId, src, state)
end)

-- ── DISCONNECT CLEANUP ────────────────────────────────────────
AddEventHandler('playerDropped', function()
    local src = source
    lastAction[src] = nil
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        local ps = Player(pid).state
        if ps.escortedBy == src then
            ps:set('isEscorted', false, true)
            ps:set('escortedBy', nil,   true)
            TriggerClientEvent('mm_police:client:escort', pid, src, false)
        end
    end
    local ds = Player(src).state
    if ds.isHandcuffed then
        ds:set('isHandcuffed', false, true)
        ds:set('handcuffMode', nil,   true)
        ds:set('isEscorted',   false, true)
        ds:set('escortedBy',   nil,   true)
    end
end)

-- ── RESOURCE STOP CLEANUP ─────────────────────────────────────
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, pid in ipairs(GetPlayers()) do
        pid = tonumber(pid)
        local ps = Player(pid).state
        if ps.isHandcuffed then
            ps:set('isHandcuffed', false, true)
            ps:set('handcuffMode', nil,   true)
            ps:set('isEscorted',   false, true)
            ps:set('escortedBy',   nil,   true)
            TriggerClientEvent('mm_police:client:handcuff', pid, false, nil)
        end
    end
end)