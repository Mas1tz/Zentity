--[[
    Alt herunder kræver Permissions.IsOwner(source) — IKKE bare IsStaff.
    Audit-loggen er bevidst kun tilgængelig herfra, jf. kravet om at Staff
    ikke må se den komplette owner audit log.
]]

lib.callback.register('mm_sf:server:ownerGetSettings', function(source)
    if not Permissions.IsOwner(source) then return nil end
    return Settings.GetAllForUI()
end)

lib.callback.register('mm_sf:server:ownerUpdateSetting', function(source, payload)
    if not Permissions.IsOwner(source) then return false, 'Ingen adgang.' end
    payload = payload or {}

    local actorIdentifier, actorName = GetIdentifier(source), GetPlayerName(source)
    local ok, err = Settings.Set(payload.key, payload.value, actorIdentifier, actorName)
    return ok, err, ok and Settings.GetAllForUI() or nil
end)

lib.callback.register('mm_sf:server:ownerGetTasks', function(source)
    if not Permissions.IsOwner(source) then return {} end

    local out = {}
    for key, taskDef in pairs(Config.Samfundstjeneste.Tasks) do
        out[#out + 1] = { key = key, label = taskDef.label, enabled = taskDef.enabled }
    end
    return out
end)

lib.callback.register('mm_sf:server:ownerToggleTask', function(source, payload)
    if not Permissions.IsOwner(source) then return false, 'Ingen adgang.' end
    payload = payload or {}

    local taskDef = payload.taskKey and Config.Samfundstjeneste.Tasks[payload.taskKey]
    if not taskDef then return false, 'Ukendt task.' end

    taskDef.enabled = payload.enabled and true or false

    local actorIdentifier, actorName = GetIdentifier(source), GetPlayerName(source)
    InsertAuditLog('change_config', actorIdentifier, actorName, nil, nil, {
        task = payload.taskKey, enabled = taskDef.enabled,
    })

    return true
end)

lib.callback.register('mm_sf:server:ownerGetAuditLog', function(source, offset)
    if not Permissions.IsOwner(source) then return {} end
    if not DatabaseReady then return {} end

    offset = tonumber(offset) or 0

    return exports.oxmysql:querySync(
        'SELECT action, actor_name, target_name, details, created_at FROM sf_auditlog ORDER BY created_at DESC LIMIT 50 OFFSET ?',
        { offset }
    ) or {}
end)

lib.callback.register('mm_sf:server:ownerGetStatistics', function(source)
    if not Permissions.IsOwner(source) then return nil end
    if not DatabaseReady then return nil end

    local totals = exports.oxmysql:singleSync([[
        SELECT
            COUNT(*)                     AS totalPlayers,
            SUM(total_assigned)          AS totalAssigned,
            SUM(total_completed)         AS totalCompleted,
            AVG(trust_factor)            AS avgTrust,
            MIN(trust_factor)            AS minTrust,
            MAX(trust_factor)            AS maxTrust
        FROM sf_players
    ]], {})

    local autoRemoved = exports.oxmysql:singleSync([[
        SELECT COALESCE(SUM(-amount), 0) AS total
        FROM sf_history
        WHERE amount < 0 AND reason = 'Automatisk tidsreduktion'
    ]], {})

    local manualRemoved = exports.oxmysql:singleSync([[
        SELECT COALESCE(SUM(-amount), 0) AS total
        FROM sf_history
        WHERE amount < 0 AND reason != 'Automatisk tidsreduktion' AND reason != 'Gennemført arbejdsopgave'
    ]], {})

    local activePlayers = 0
    for _, data in pairs(Players) do
        if data.inService then activePlayers = activePlayers + 1 end
    end

    return {
        totalPlayers = tonumber(totals and totals.totalPlayers) or 0,
        totalAssigned = tonumber(totals and totals.totalAssigned) or 0,
        totalCompleted = tonumber(totals and totals.totalCompleted) or 0,
        avgTrust = Utils.Round(tonumber(totals and totals.avgTrust) or 0, 1),
        minTrust = tonumber(totals and totals.minTrust) or 0,
        maxTrust = tonumber(totals and totals.maxTrust) or 0,
        activePlayers = activePlayers,
        autoRemoved = tonumber(autoRemoved and autoRemoved.total) or 0,
        manualRemoved = tonumber(manualRemoved and manualRemoved.total) or 0,
    }
end)
