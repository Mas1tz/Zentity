-- ============================================================
-- MM-PolitiJob - server/main.lua
-- Politi-aktivitetstid, disconnect cleanup, hire, misc
--
-- INGEN duty-system. "Aktiv tid" for boss-menuen tælles nu
-- automatisk fra det øjeblik en spillers job bliver politi, til
-- det øjeblik det holder op med at være det (jobskifte,
-- disconnect, eller resource restart).
-- ============================================================

local activityTimers = {}   -- [src] = os.time() da spilleren blev politi

-- ── START/STOP AKTIV-TID ──────────────────────────────────────
local function StartActivity(src)
    if activityTimers[src] then return end -- allerede kørende
    activityTimers[src] = os.time()
end

local function StopActivity(src)
    local startedAt = activityTimers[src]
    if not startedAt then return end
    activityTimers[src] = nil

    local minutes = math.floor(os.difftime(os.time(), startedAt) / 60)
    if minutes <= 0 then return end

    local identifier = SV.Framework.GetIdentifier(src)
    if not identifier then return end

    local charName = SV.Framework.GetName(src)
    DB_SaveTime(identifier, charName, minutes)
end

-- Kaldes hver gang vi får at vide hvad en spillers job er
-- (login, jobskifte). Beslutter selv om timeren skal starte/stoppe.
local function SyncActivity(src, jobName)
    local isPolice = false
    for _, j in ipairs(Config.PoliceJobs) do
        if j == jobName then isPolice = true break end
    end

    if isPolice then
        StartActivity(src)
    else
        StopActivity(src)
    end
end

-- ── LOGIN: START TIMER HVIS ALLEREDE POLITI ──────────────────
AddEventHandler('esx:playerLoaded', function(src, xPlayer)
    if xPlayer and xPlayer.job then
        SyncActivity(src, xPlayer.job.name)
    end
end)

AddEventHandler('QBCore:Server:OnPlayerLoaded', function(src)
    local p = SV.Framework.GetPlayer(src)
    if p and p.PlayerData and p.PlayerData.job then
        SyncActivity(src, p.PlayerData.job.name)
    end
end)

-- Resource (re)start mens spillere allerede er online og politi
CreateThread(function()
    Wait(2000) -- vent på at framework/spillerdata er klar
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        local job = SV.Framework.GetJob(src)
        if job then SyncActivity(src, job) end
    end
end)

-- ── JOBSKIFTE ────────────────────────────────────────────────
AddEventHandler('esx:setJob', function(src, job)
    if job then SyncActivity(src, job.name) end
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job)
    if job then SyncActivity(src, job.name) end
end)

-- ── DISCONNECT ───────────────────────────────────────────────
AddEventHandler('playerDropped', function()
    StopActivity(source)
end)

-- ── RESOURCE STOP: gem tid for alle der er aktive lige nu ─────
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src, _ in pairs(activityTimers) do
        StopActivity(src)
    end
end)

-- ── HIRE ────────────────────────────────────────────────────
RegisterNetEvent('mm_police:server:hire', function(targetId)
    local src = source
    if not SV.Framework.IsPolice(src) then return end
    if not SV.Framework.HasMinGrade(src, Config.BossMinGrade) then return end

    targetId = tonumber(targetId)
    if not targetId or not GetPlayerName(targetId) then
        SV_Notify(src, 'Fejl', 'Spiller ikke fundet.', 'error')
        return
    end

    SV.Framework.SetJob(targetId, Config.PoliceJobs[1], 0)
    SyncActivity(targetId, Config.PoliceJobs[1])

    SV_Notify(src, 'Ansat', SV.Framework.GetName(targetId) .. ' er nu ansat.', 'success')
end)

-- ── NOTIFY TIL KLIENT ────────────────────────────────────────
-- Central wrapper: al server-side notify går gennem denne, så
-- position kun skal styres ét sted (rule: kun 'center-right' eller
-- 'bottom' bruges nogen steder i resource'en).
function SV_Notify(src, title, desc, ntype)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = title,
        description = desc,
        type        = ntype or 'inform',
        duration    = 5000,
        position    = 'center-right',
    })
end
