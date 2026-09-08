-- ============================================================
-- MM-PolitiJob - server/framework.lua
-- Server-side framework abstraction. Ét sted for al ESX/QB logik.
-- Retry-loop sikrer at _fw ikke forbliver nil for evigt hvis
-- es_extended/qb-core ikke er "started" i det præcise
-- millisekund denne tråd kører ved server-boot.
-- ============================================================

SV = SV or {}
SV.Framework = {}

local _fw  = nil
local _esx = nil
local _qb  = nil

CreateThread(function()
    -- Første forsøg med det samme
    if Config.Framework == 'esx' or Config.Framework == 'auto' then
        if GetResourceState('es_extended') == 'started' then
            _esx = exports['es_extended']:getSharedObject()
            _fw  = 'esx'
            if Config.Debug then print('[MM-PolitiJob] Server Framework: ^3ESX') end
            return
        end
    end
    if Config.Framework == 'qb' or Config.Framework == 'auto' then
        if GetResourceState('qb-core') == 'started' then
            _qb = exports['qb-core']:GetCoreObject()
            _fw = 'qb'
            if Config.Debug then print('[MM-PolitiJob] Server Framework: ^3QBCore') end
            return
        end
    end

    -- Retry-loop - prøv igen hvert 500ms indtil frameworket er startet.
    while not _fw do
        Wait(500)
        if (Config.Framework == 'esx' or Config.Framework == 'auto')
            and GetResourceState('es_extended') == 'started' then
            _esx = exports['es_extended']:getSharedObject()
            _fw  = 'esx'
            if Config.Debug then print('[MM-PolitiJob] Server Framework (retry): ^3ESX') end
        elseif (Config.Framework == 'qb' or Config.Framework == 'auto')
            and GetResourceState('qb-core') == 'started' then
            _qb = exports['qb-core']:GetCoreObject()
            _fw = 'qb'
            if Config.Debug then print('[MM-PolitiJob] Server Framework (retry): ^3QBCore') end
        end
    end
end)

function SV.Framework.GetType() return _fw end

-- ── HENT SPILLER OBJEKT ──────────────────────────────────────
function SV.Framework.GetPlayer(src)
    if not src then return nil end
    if _fw == 'esx' and _esx then return _esx.GetPlayerFromId(src) end
    if _fw == 'qb'  and _qb  then return _qb.Functions.GetPlayer(src) end
    return nil
end

-- ── HENT IDENTIFIER ──────────────────────────────────────────
function SV.Framework.GetIdentifier(src)
    local p = SV.Framework.GetPlayer(src)
    if not p then return nil end
    if _fw == 'esx' then return p.getIdentifier() end
    if _fw == 'qb'  then return p.PlayerData.citizenid end
    return nil
end

-- ── HENT NAVN ────────────────────────────────────────────────
function SV.Framework.GetName(src)
    local p = SV.Framework.GetPlayer(src)
    if not p then return GetPlayerName(src) or 'Ukendt' end
    if _fw == 'esx' then return p.getName() end
    if _fw == 'qb'  then
        local ci = p.PlayerData.charinfo
        return (ci and (ci.firstname .. ' ' .. ci.lastname)) or GetPlayerName(src) or 'Ukendt'
    end
    return GetPlayerName(src) or 'Ukendt'
end

-- ── HENT JOB ─────────────────────────────────────────────────
function SV.Framework.GetJob(src)
    local p = SV.Framework.GetPlayer(src)
    if not p then return nil, 0 end
    if _fw == 'esx' then
        return p.job and p.job.name, (p.job and p.job.grade) or 0
    end
    if _fw == 'qb' then
        local job = p.PlayerData.job
        return job and job.name, (job and job.grade and job.grade.level) or 0
    end
    return nil, 0
end

-- ── ER POLITI ────────────────────────────────────────────────
-- Dette er DEN centrale server-side check. Serveren stoler ALDRIG
-- på klientens IsPolice() - alt der er sikkerhedskritisk skal
-- validere jobbet her, server-side, mod spillerens faktiske data.
function SV.Framework.IsPolice(src)
    local job = SV.Framework.GetJob(src)
    if not job then return false end
    for _, j in ipairs(Config.PoliceJobs) do
        if j == job then return true end
    end
    return false
end

-- ── GRADE CHECK ──────────────────────────────────────────────
function SV.Framework.HasMinGrade(src, minGrade)
    local _, grade = SV.Framework.GetJob(src)
    return grade >= (minGrade or 0)
end

-- ── GIVE ITEM ────────────────────────────────────────────────
function SV.Framework.GiveItem(src, itemName, amount)
    -- ox_inventory foretrækkes altid
    return exports.ox_inventory:AddItem(src, itemName, amount or 1)
end

-- ── SET JOB (online spiller) ──────────────────────────────────
function SV.Framework.SetJob(src, job, grade)
    local p = SV.Framework.GetPlayer(src)
    if not p then return end
    if _fw == 'esx' then p.setJob(job, grade or 0) end
    if _fw == 'qb'  then p.Functions.SetJob(job, grade or 0) end
end

-- ── OFFLINE OPDATERING (bossmenu: sæt grade / fyr betjent) ────
-- Bossmenuen skal kunne ændre grade/job for medarbejdere der IKKE
-- er online. Dette kræver framework-specifik SQL, da ESX og QBCore
-- bruger helt forskellige tabeller/kolonner. Tidligere kørte
-- bossmenu.lua rå ESX-SQL uden nogen framework-check overhovedet,
-- hvilket ville fejle stille (0 rows affected) på QBCore.
function SV.Framework.SetGradeOffline(identifier, grade)
    if not identifier or not grade then return end
    if _fw == 'esx' then
        MySQL.update('UPDATE users SET job_grade = ? WHERE identifier = ?', { grade, identifier })
    elseif _fw == 'qb' then
        -- Bedste indsats: opdaterer kun grade-level i job JSON.
        -- QBCore's grade-label hentes normalt fra shared/jobs.lua ud
        -- fra level ved næste login, så dette er tilstrækkeligt for
        -- de fleste QB-opsætninger.
        MySQL.update(
            "UPDATE players SET job = JSON_SET(job, '$.grade.level', ?) WHERE citizenid = ?",
            { grade, identifier }
        )
    end
end

function SV.Framework.SetJobOffline(identifier, job, grade)
    if not identifier or not job then return end
    if _fw == 'esx' then
        MySQL.update('UPDATE users SET job = ?, job_grade = ? WHERE identifier = ?',
            { job, grade or 0, identifier })
    elseif _fw == 'qb' then
        MySQL.update(
            "UPDATE players SET job = JSON_SET(job, '$.name', ?, '$.grade.level', ?) WHERE citizenid = ?",
            { job, grade or 0, identifier }
        )
    end
end
