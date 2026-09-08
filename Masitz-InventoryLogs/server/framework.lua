-- ============================================================
--  Masitz-InventoryLogs | server/framework.lua
--  Thin, defensive ESX Legacy bridge. Every lookup is wrapped in
--  pcall - a player disconnecting mid-action, or ESX not being
--  fully ready yet, must never throw inside an ox_inventory hook.
-- ============================================================

Framework = {}

local ESX = nil

local function waitForESX()
    while GetResourceState('es_extended') ~= 'started' do
        Wait(250)
    end

    local ok, obj = pcall(function()
        return exports['es_extended']:getSharedObject()
    end)

    if ok and obj then
        ESX = obj
        Utils.DebugPrint('ESX shared object acquired.')
    else
        Utils.Warn('Failed to acquire the ESX shared object - player info (job/identifier/name) will be limited to server id and character name until this resolves.')
    end
end

CreateThread(waitForESX)

---@param source number
---@return table? xPlayer
local function getXPlayer(source)
    if not ESX or type(source) ~= 'number' then return nil end

    local ok, xPlayer = pcall(ESX.GetPlayerFromId, source)
    if not ok then return nil end

    return xPlayer
end

---Builds a server-authoritative info block for a player. Never trusts
---anything the client provided - `source` is the only input, and every
---field is resolved from ESX/natives on the server.
---@param source number?
---@return table
function Framework.GetPlayerInfo(source)
    local info = {
        source = source,
        name = nil,
        identifier = nil,
        charName = nil,
        job = nil,
        jobLabel = nil,
        grade = nil,
        gradeLabel = nil,
    }

    if type(source) ~= 'number' then
        info.name = 'Unknown'
        return info
    end

    local okName, name = pcall(GetPlayerName, source)
    info.name = (okName and name) or 'Unknown'

    local xPlayer = getXPlayer(source)
    if not xPlayer then return info end

    local okIdentifier, identifier = pcall(function() return xPlayer.identifier end)
    if okIdentifier then info.identifier = identifier end

    local okCharName, charName = pcall(function()
        if xPlayer.getName then return xPlayer.getName() end
        return nil
    end)
    if okCharName and charName and charName ~= '' then info.charName = charName end

    local okJob, job = pcall(function() return xPlayer.job end)
    if okJob and type(job) == 'table' then
        info.job = job.name
        info.jobLabel = job.label
        info.grade = job.grade
        info.gradeLabel = job.grade_label or job.grade_name
    end

    return info
end

---@return boolean
function Framework.IsReady()
    return ESX ~= nil
end
