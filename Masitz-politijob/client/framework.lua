-- ============================================================
-- MM-PolitiJob - client/framework.lua
-- Én fil der håndterer alt framework logik.
-- Alle andre filer bruger kun MM.Framework.*
--
-- Dette er også den ENESTE fil der lytter på esx:setJob /
-- QBCore:Client:OnJobUpdate. Alle andre filer der har brug for at
-- reagere på jobskifte skal lytte på det lokale event
-- 'mm:policeStatusChanged' som MM.State.UpdateJob sender ud
-- (se client/state.lua). Det undgår at samme logik/handlers
-- duplikeres i flere filer.
-- ============================================================

MM = MM or {}
MM.Framework = {}

local _fw  = nil   -- internt: "esx" | "qb"
local _esx = nil
local _qb  = nil

-- ── INIT ─────────────────────────────────────────────────────
-- Kaldes én gang fra client/main.lua
function MM.Framework.Init(cb)
    CreateThread(function()
        -- ESX
        if Config.Framework == "esx" or Config.Framework == "auto" then
            if GetResourceState('es_extended') == 'started' then
                _esx = exports['es_extended']:getSharedObject()
                _fw  = "esx"
                if cb then cb("esx") end
                return
            end
        end
        -- QBCore
        if Config.Framework == "qb" or Config.Framework == "auto" then
            if GetResourceState('qb-core') == 'started' then
                _qb = exports['qb-core']:GetCoreObject()
                _fw = "qb"
                if cb then cb("qb") end
                return
            end
        end
        -- Retry loop - dependency-resourcen kan starte lidt senere end os
        while true do
            Wait(500)
            if (Config.Framework == "esx" or Config.Framework == "auto")
                and GetResourceState('es_extended') == 'started' then
                _esx = exports['es_extended']:getSharedObject()
                _fw  = "esx"
                if cb then cb("esx") end
                return
            elseif (Config.Framework == "qb" or Config.Framework == "auto")
                and GetResourceState('qb-core') == 'started' then
                _qb = exports['qb-core']:GetCoreObject()
                _fw = "qb"
                if cb then cb("qb") end
                return
            end
        end
    end)
end

-- ── GETTERS ──────────────────────────────────────────────────

function MM.Framework.GetType()
    return _fw
end

function MM.Framework.GetPlayerData()
    if _fw == "esx" and _esx then
        return _esx.GetPlayerData()
    elseif _fw == "qb" and _qb then
        return _qb.Functions.GetPlayerData()
    end
    return nil
end

function MM.Framework.GetJob()
    local pd = MM.Framework.GetPlayerData()
    if not pd or not pd.job then return nil, 0 end
    if _fw == "esx" then
        return pd.job.name, pd.job.grade or 0
    elseif _fw == "qb" then
        return pd.job.name, (pd.job.grade and pd.job.grade.level) or 0
    end
    return nil, 0
end

function MM.Framework.GetPlayerName()
    local pd = MM.Framework.GetPlayerData()
    if not pd then return GetPlayerName(PlayerId()) end
    if _fw == "esx" then
        return (pd.firstName and (pd.firstName .. ' ' .. (pd.lastName or ''))) or GetPlayerName(PlayerId())
    elseif _fw == "qb" then
        local ci = pd.charinfo
        return (ci and ci.firstname and (ci.firstname .. ' ' .. (ci.lastname or ''))) or GetPlayerName(PlayerId())
    end
    return GetPlayerName(PlayerId())
end

-- ── HELPERS ──────────────────────────────────────────────────

-- Er spilleren politi? Dette er DEN centrale check.
-- Alle andre filer (client + fremtidige tilføjelser) skal bruge denne.
function MM.Framework.IsPolice()
    local job = MM.Framework.GetJob()
    if not job then return false end
    for _, j in ipairs(Config.PoliceJobs) do
        if j == job then return true end
    end
    return false
end

-- Grade check
function MM.Framework.HasMinGrade(minGrade)
    local _, grade = MM.Framework.GetJob()
    return grade >= (minGrade or 0)
end

-- ── JOB EVENT HOOKS ──────────────────────────────────────────
-- Eneste sted i resource'en der lytter på disse. Skal bruge
-- RegisterNetEvent (ikke bare AddEventHandler) da events trigges
-- af serveren via TriggerClientEvent.

RegisterNetEvent('esx:setJob', function(job)
    if not job then return end
    if MM.State then MM.State.UpdateJob(job.name, job.grade or 0) end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    if not job then return end
    if MM.State then
        MM.State.UpdateJob(job.name, (job.grade and job.grade.level) or 0)
    end
end)

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    Wait(1000)
    if xPlayer and xPlayer.job and MM.State then
        MM.State.UpdateJob(xPlayer.job.name, xPlayer.job.grade or 0)
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(1000)
    if not _qb then return end
    local playerData = _qb.Functions.GetPlayerData()
    if playerData and playerData.job and MM.State then
        MM.State.UpdateJob(playerData.job.name, (playerData.job.grade and playerData.job.grade.level) or 0)
    end
end)
