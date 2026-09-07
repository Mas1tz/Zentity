-- ============================================================
--  kc_mdt | server/sv_dashboard.lua  (v2.0.3)
--  Dashboard — ox_lib callbacks kører allerede i coroutine,
--  så MySQL.await fungerer direkte. Ingen promise-wrapper.
-- ============================================================

lib.callback.register('kcmdt:getDashboard', function(src)
    if not KCS.requireSession(src) then
        -- Returnér en tom struktur så NUI får valid JSON
        return {
            stats = { activeWarrants=0, openCases=0, todayArrests=0, activeDispatches=0, onlineOfficers=0 },
            recentArrests = {}, recentCases = {}, recentWarrants = {},
            topOfficers = {}, activeDispatches = {}, patrolList = {},
        }
    end

    -- Stats (sekventielle, men hver MySQL await yielder)
    local stats = {
        activeWarrants   = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM polititablet_warrants WHERE active=1', {})) or 0,
        openCases        = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM polititablet_cases WHERE status IN('open','investigating')", {})) or 0,
        todayArrests     = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM polititablet_arrests WHERE DATE(created_at)=CURDATE()', {})) or 0,
        activeDispatches = tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM polititablet_dispatches WHERE status='active'", {})) or 0,
        onlineOfficers   = 0,
    }
    local n = 0; for _ in pairs(KCS.online) do n = n + 1 end
    stats.onlineOfficers = n

    local recentArrests = MySQL.query.await([[
        SELECT a.id, a.officer_name, a.total_fine, a.total_jail, a.created_at,
               u.firstname, u.lastname
        FROM polititablet_arrests a
        LEFT JOIN users u ON u.identifier = a.citizenid
        ORDER BY a.created_at DESC
        LIMIT 5
    ]], {}) or {}

    local recentCases = MySQL.query.await([[
        SELECT id, case_number, title, status, created_by, created_at
        FROM polititablet_cases
        ORDER BY created_at DESC
        LIMIT 5
    ]], {}) or {}

    local recentWarrants = MySQL.query.await([[
        SELECT w.id, w.citizenid, w.reason, w.risk_level, w.issued_by, w.created_at,
               u.firstname, u.lastname
        FROM polititablet_warrants w
        LEFT JOIN users u ON u.identifier = w.citizenid
        WHERE w.active=1
        ORDER BY w.created_at DESC
        LIMIT 5
    ]], {}) or {}

    local topOfficers = MySQL.query.await([[
        SELECT a.username, a.rank, a.badge_number, SUM(d.seconds) AS total_sec
        FROM polititablet_duty_log d
        INNER JOIN polititablet_accounts a ON a.identifier = d.identifier
        WHERE d.duty_on >= DATE_SUB(NOW(), INTERVAL 7 DAY)
        GROUP BY a.id
        ORDER BY total_sec DESC
        LIMIT 5
    ]], {}) or {}

    local activeDispatches = MySQL.query.await([[
        SELECT id, code, description, location, priority, status, created_at
        FROM polititablet_dispatches
        WHERE status != 'resolved'
        ORDER BY priority DESC, created_at DESC
        LIMIT 10
    ]], {}) or {}

    return {
        stats            = stats,
        recentArrests    = recentArrests,
        recentCases      = recentCases,
        recentWarrants   = recentWarrants,
        topOfficers      = topOfficers,
        activeDispatches = activeDispatches,
        patrolList       = KCS.getPatrolList(),
    }
end)
