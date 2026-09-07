-- ============================================================
--  kc_mdt | server/sv_dispatch.lua
--  Dispatch system — coords verified server-side (no spoof)
-- ============================================================

lib.callback.register('kcmdt:getDispatches', function(src)
    if not KCS.requireSession(src) then return {} end
    return MySQL.query.await([[
        SELECT id, code, description, location, coords_x, coords_y, priority, status, created_by, created_at, units
        FROM polititablet_dispatches
        WHERE status != 'resolved'
        ORDER BY priority DESC, created_at DESC
        LIMIT 50
    ]], {}) or {}
end)

RegisterNetEvent('kcmdt:createDispatch', function(payload)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.requirePermission(src, 'createDispatch') then return end
    if not KCS.spamCheck(src) then return end
    if type(payload) ~= 'table' or not payload.description then return end

    -- Verificér koordinater serverside (klient kan ikke spoofe).
    local ped = GetPlayerPed(src)
    local cx, cy = nil, nil
    if ped and ped ~= 0 then
        local c = GetEntityCoords(ped)
        cx, cy = c.x, c.y
    end

    local code        = KC.safeStr(payload.code or 'UKENDT', 20) -- §6: ingen amerikanske 10-koder som default
    local description = KC.safeStr(payload.description, 1500)
    local location    = KC.safeStr(payload.location or '', 255)
    local priority    = KC.clampInt(payload.priority or 2, 1, 3)
    local units       = json.encode(payload.units or {})

    -- Named parametre: cx/cy er nil når spillerens ped ikke kunne læses
    -- (ped==0), hvilket ellers ville lave et hul midt i en positionel
    -- `?`-array og potentielt afkorte iterationen før priority/created_by/
    -- units (se samme fix i sv_persons.lua/sv_patrol.lua/sv_cases.lua).
    local id = MySQL.insert.await([[
        INSERT INTO polititablet_dispatches (code,description,location,coords_x,coords_y,priority,created_by_id,created_by,units)
        VALUES (:code,:description,:location,:coordsX,:coordsY,:priority,:createdById,:createdBy,:units)
    ]], {
        code = code, description = description, location = location,
        coordsX = cx, coordsY = cy, priority = priority,
        createdById = sess.identifier, createdBy = sess.rawName, units = units,
    })

    KCS.broadcastMDT('kcmdt:newDispatch', {
        id          = id,
        code        = code,
        description = description,
        location    = location,
        priority    = priority,
        coords_x    = cx,
        coords_y    = cy,
        created_by  = sess.rawName,
        created_at  = os.date('%Y-%m-%d %H:%M:%S'),
    })

    KCS.audit(sess.identifier, sess.rawName, 'CREATE_DISPATCH', code, description:sub(1, 100))
    TriggerClientEvent('kcmdt:notify', src, 'Dispatch sendt.', 'success')
end)

RegisterNetEvent('kcmdt:resolveDispatch', function(dispatchId)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.requirePermission(src, 'resolveDispatch') then return end
    dispatchId = tonumber(dispatchId); if not dispatchId then return end

    local updated = MySQL.update.await(
        "UPDATE polititablet_dispatches SET status='resolved', resolved_at=NOW(), resolved_by=? WHERE id=? AND status!='resolved'",
        { sess.rawName, dispatchId }
    )

    if updated and updated > 0 then
        KCS.broadcastMDT('kcmdt:dispatchResolved', { id = dispatchId, by = sess.rawName })
        KCS.audit(sess.identifier, sess.rawName, 'RESOLVE_DISPATCH', tostring(dispatchId), nil)
    end
end)
