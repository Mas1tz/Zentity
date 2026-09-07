-- ============================================================
--  kc_mdt | server/sv_polititablet.lua
--  Core state, helpers, sessions, audit, permissions
-- ============================================================

ESX = exports['es_extended']:getSharedObject()

KCS = KCS or {}  -- server-side namespace

-- ─── STATE ───────────────────────────────────────────────────
KCS.online        = {}    -- [identifier] = session table
KCS.bySrc         = {}    -- [src]        = identifier  (reverse lookup)
KCS.spamCool      = {}    -- [src]        = ms timestamp
KCS.gpsCache      = {}    -- [identifier] = { x, y, z, lastWrite }
KCS.caseSeq       = 0
KCS.staticCache   = {}    -- charges/laws cache
KCS.cacheVersion  = 0

-- ─── XPLAYER HELPERS ─────────────────────────────────────────
function KCS.getXP(src)
    if not src or src == 0 then return nil end
    return ESX.GetPlayerFromId(src)
end

function KCS.getSession(src)
    local id = KCS.bySrc[src]
    if not id then
        local xp = KCS.getXP(src)
        if not xp then return nil end
        id = xp.identifier
    end
    return KCS.online[id]
end

-- Returns session OR nil + sends notify to client.
function KCS.requireSession(src)
    local sess = KCS.getSession(src)
    if not sess then
        TriggerClientEvent('kcmdt:notify', src, 'Ikke logget ind i MDT.', 'error')
        return nil
    end
    -- Touch session
    sess.lastActive = os.time()
    return sess
end

-- ─── PERMISSIONS ─────────────────────────────────────────────
function KCS.hasGrade(src, minGrade)
    local xp = KCS.getXP(src)
    if not xp then return false end
    if not Config.AllowedJobs[xp.job and xp.job.name] then return false end
    return (xp.job.grade or 0) >= (minGrade or 0)
end

function KCS.requirePermission(src, key)
    local minGrade = Config.Permissions[key] or 999
    if not KCS.hasGrade(src, minGrade) then
        TriggerClientEvent('kcmdt:notify', src,
            ('Du har ikke tilladelse til denne handling (kræver grade %d+).'):format(minGrade), 'error')
        return false
    end
    return true
end

-- ─── ANTI-SPAM ───────────────────────────────────────────────
function KCS.spamCheck(src)
    local now = GetGameTimer()
    local last = KCS.spamCool[src] or 0
    if (now - last) < Config.SpamThrottleMS then
        TriggerClientEvent('kcmdt:notify', src, 'For mange handlinger på kort tid. Vent et øjeblik.', 'warning')
        return false
    end
    KCS.spamCool[src] = now
    return true
end

-- ─── AUDIT LOG ───────────────────────────────────────────────
function KCS.audit(actorId, actorName, action, target, details)
    -- Fire-and-forget; ingen .await for ikke at blokere
    MySQL.insert(
        'INSERT INTO polititablet_audit_log (actor_id,actor_name,action,target,details) VALUES (?,?,?,?,?)',
        { actorId or 'SYSTEM', actorName or 'System',
          action, KC.safeStr(target, 255), KC.safeStr(details, 1000) }
    )
end

-- ─── PATROL LIST GENERATOR ───────────────────────────────────
-- vehicleNetId (§22 — Flådestyring) er sat af cl_polititablet.lua's
-- GPS-tick (kun ved reel ændring, se KCS.setVehicleState) og bruges af
-- NUI'en til at gruppere betjente, der reelt sidder i samme køretøj.
function KCS.getPatrolList()
    local list = {}
    for ident, s in pairs(KCS.online) do
        list[#list+1] = {
            identifier   = ident,
            name         = s.name,
            grade        = s.grade,
            rank         = s.rank,
            unit         = s.unit,
            status       = s.status or 1,
            badge        = s.badgeNum,
            coords       = s.coords,
            vehicleLabel = s.vehicleLabel,
            vehicleNetId = s.vehicleNetId,
            seatRole     = s.seatRole,
        }
    end
    return list
end

-- Broadcast til alle online MDT-betjente (ikke -1, kun de der er logget ind).
function KCS.broadcastMDT(eventName, ...)
    for _, sess in pairs(KCS.online) do
        if sess.source then
            TriggerClientEvent(eventName, sess.source, ...)
        end
    end
end

function KCS.broadcastPatrolList()
    KCS.broadcastMDT('kcmdt:updatePatrolList', KCS.getPatrolList())
end

-- ─── CASE NUMBER GENERATOR ───────────────────────────────────
function KCS.generateCaseNum()
    KCS.caseSeq = KCS.caseSeq + 1
    return ('SAG-%s-%04d'):format(os.date('%Y'), KCS.caseSeq)
end

-- ─── DISCORD / CONSOLE NOTIFY (placeholder) ──────────────────
function KCS.consoleLog(action, msg)
    print(('^2[kc_mdt %s]^7 %s'):format(action, msg))
end

-- ─── SESSION TIMEOUT WATCHDOG ────────────────────────────────
-- Tjek hvert minut for inaktive sessions.
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        local timeoutSec = Config.Security.sessionTimeoutMin * 60
        for ident, sess in pairs(KCS.online) do
            if sess.lastActive and (now - sess.lastActive) > timeoutSec then
                KC.log('main', 'Session timeout for %s', ident)
                if sess.source then
                    TriggerClientEvent('kcmdt:forceLogout', sess.source, 'Session udløbet — log ind igen.')
                end
                -- Force-clean
                if KCS.endSession then KCS.endSession(ident, 'timeout') end
            end
        end
    end
end)

-- ─── RESOURCE START: restore state ───────────────────────────
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetTimeout(800, function()
        -- Load case sequence
        local row = MySQL.scalar.await('SELECT MAX(id) FROM polititablet_cases', {})
        KCS.caseSeq = tonumber(row) or 0

        -- Close orphan duty sessions (server restart)
        MySQL.update.await(
            "UPDATE polititablet_duty_log SET duty_off=NOW(), seconds=TIMESTAMPDIFF(SECOND,duty_on,NOW()) WHERE duty_off IS NULL",
            {}
        )

        -- Clear stale patrol units (older than 5 minutes)
        MySQL.update.await(
            "DELETE FROM polititablet_patrol_units WHERE last_update < DATE_SUB(NOW(), INTERVAL 5 MINUTE)",
            {}
        )

        -- Auto-unlock accounts whose lock has expired
        MySQL.update.await(
            "UPDATE polititablet_accounts SET locked_until=NULL, failed_attempts=0 WHERE locked_until IS NOT NULL AND locked_until < NOW()",
            {}
        )

        KCS.consoleLog('START', ('Initialised. caseSeq=%d'):format(KCS.caseSeq))
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- Close all duty logs cleanly
    MySQL.update.await(
        "UPDATE polititablet_duty_log SET duty_off=NOW(), seconds=TIMESTAMPDIFF(SECOND,duty_on,NOW()) WHERE duty_off IS NULL",
        {}
    )
    MySQL.update.await("DELETE FROM polititablet_patrol_units", {})
end)

-- ─── PLAYER DROPPED — clean session ──────────────────────────
AddEventHandler('playerDropped', function()
    local src = source
    local id  = KCS.bySrc[src]
    if id and KCS.online[id] then
        if KCS.endSession then KCS.endSession(id, 'dropped') end
    end
    KCS.bySrc[src]    = nil
    KCS.spamCool[src] = nil
end)