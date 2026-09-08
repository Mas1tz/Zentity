-- ══════════════════════════════════════════════════════════
--  FRAMEWORK ABSTRACTION — mm-christmas
--
--  Framework.type is detected synchronously (no CreateThread) so it is
--  guaranteed to be resolved before any other server file executes -
--  the original version detected inside a CreateThread with no
--  guarantee it had finished before the first "playerJoin" event fired.
-- ══════════════════════════════════════════════════════════

Framework = {}
Framework.type = 'standalone'
Framework.obj  = nil

local function tryESX()
    local ok, esx = pcall(function() return exports['es_extended']:getSharedObject() end)
    if ok and esx then
        Framework.type = 'esx'
        Framework.obj  = esx
        return true
    end
    return false
end

local function tryQBCore()
    local ok, qb = pcall(function() return exports['qb-core']:GetCoreObject() end)
    if ok and qb then
        Framework.type = 'qbcore'
        Framework.obj  = qb
        return true
    end
    return false
end

-- vRP has several incompatible community forks. This targets the common
-- "global vRP proxy" convention (vRP.getUserId / vRP.hasPermission etc.,
-- exposed as a global table by the vRP resource itself). If your vRP
-- fork exposes a different API, adjust the functions below accordingly -
-- this integration could not be verified against a live vRP server.
local function tryVRP()
    local ok = pcall(function() return type(vRP) == 'table' and type(vRP.getUserId) == 'function' end)
    if ok and type(vRP) == 'table' and type(vRP.getUserId) == 'function' then
        Framework.type = 'vrp'
        Framework.obj  = vRP
        return true
    end
    return false
end

local function detect()
    if Config.Framework == 'esx' then
        if tryESX() then return end
    elseif Config.Framework == 'qbcore' then
        if tryQBCore() then return end
    elseif Config.Framework == 'vrp' then
        if tryVRP() then return end
    elseif Config.Framework == 'standalone' then
        Framework.type = 'standalone'
        return
    elseif Config.Framework == 'auto' then
        if tryESX() then return end
        if tryQBCore() then return end
        if tryVRP() then return end
    end

    Framework.type = 'standalone'
end

detect()
Shared.Debug('Framework detected:', Framework.type)

-- ── IDENTIFIER ────────────────────────────────────────────
function Framework.GetIdentifier(src)
    if Framework.type == 'esx' then
        local xPlayer = Framework.obj.GetPlayerFromId(src)
        return xPlayer and xPlayer.getIdentifier() or nil
    elseif Framework.type == 'qbcore' then
        local Player = Framework.obj.Functions.GetPlayer(src)
        return Player and Player.PlayerData.citizenid or nil
    elseif Framework.type == 'vrp' then
        local ok, userId = pcall(function() return Framework.obj.getUserId(src) end)
        return (ok and userId) and tostring(userId) or nil
    else
        return GetPlayerIdentifierByType(src, 'license') or GetPlayerIdentifier(src, 0)
    end
end

-- ── PLAYER OBJECT ─────────────────────────────────────────
-- Returns the underlying framework player object/handle. Standalone has
-- no such object, so it returns the raw server id instead.
function Framework.GetPlayer(src)
    if Framework.type == 'esx' then
        return Framework.obj.GetPlayerFromId(src)
    elseif Framework.type == 'qbcore' then
        return Framework.obj.Functions.GetPlayer(src)
    elseif Framework.type == 'vrp' then
        local ok, userId = pcall(function() return Framework.obj.getUserId(src) end)
        return ok and userId or nil
    end
    return src
end

-- ── NAME ──────────────────────────────────────────────────
function Framework.GetName(src)
    if Framework.type == 'esx' then
        local xPlayer = Framework.obj.GetPlayerFromId(src)
        return (xPlayer and xPlayer.getName()) or GetPlayerName(src)
    elseif Framework.type == 'qbcore' then
        local Player = Framework.obj.Functions.GetPlayer(src)
        if Player and Player.PlayerData.charinfo then
            return (Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname)
        end
        return GetPlayerName(src)
    elseif Framework.type == 'vrp' then
        local ok, userId = pcall(function() return Framework.obj.getUserId(src) end)
        if ok and userId then
            local ok2, name = pcall(function() return Framework.obj.getUserName(userId) end)
            if ok2 and name then return name end
        end
        return GetPlayerName(src)
    else
        return GetPlayerName(src)
    end
end

-- ── ITEMS (ox_inventory is primary — see server/inventory.lua) ──────
-- Kept only as a last-resort fallback for setups without ox_inventory.
function Framework.GiveItemFallback(src, item, amount)
    if Framework.type == 'esx' then
        local xPlayer = Framework.obj.GetPlayerFromId(src)
        if xPlayer then xPlayer.addInventoryItem(item, amount) return true end
    elseif Framework.type == 'qbcore' then
        local Player = Framework.obj.Functions.GetPlayer(src)
        if Player then Player.Functions.AddItem(item, amount) return true end
    elseif Framework.type == 'vrp' then
        local ok = pcall(function() Framework.obj.giveInventoryItem(src, item, amount) end)
        return ok
    else
        TriggerClientEvent('mm-christmas:client:giveItem', src, item, amount)
        return true
    end
    return false
end

-- ── ADMIN CHECK ───────────────────────────────────────────
function Framework.IsAdmin(src)
    if Framework.type == 'esx' then
        local xPlayer = Framework.obj.GetPlayerFromId(src)
        if not xPlayer then return false end
        for _, g in ipairs(Config.AdminGroups) do
            if xPlayer.getGroup() == g then return true end
        end
        return false
    elseif Framework.type == 'qbcore' then
        local Player = Framework.obj.Functions.GetPlayer(src)
        if not Player then return false end
        local perm = Framework.obj.Functions.GetPermission(src)
        for _, g in ipairs(Config.AdminGroups) do
            if perm == g then return true end
        end
        return false
    elseif Framework.type == 'vrp' then
        local ok, userId = pcall(function() return Framework.obj.getUserId(src) end)
        if not ok or not userId then return false end
        for _, g in ipairs(Config.AdminGroups) do
            local okPerm, has = pcall(function() return Framework.obj.hasPermission(userId, 'admin.' .. g) end)
            if okPerm and has then return true end
        end
        return false
    else
        for _, g in ipairs(Config.AdminGroups) do
            if IsPlayerAceAllowed(src, 'group.' .. g) then return true end
        end
        return false
    end
end
