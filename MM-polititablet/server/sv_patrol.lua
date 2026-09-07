-- ============================================================
--  kc_mdt | server/sv_patrol.lua
--  Patrol units, GPS sync, panic, duty time
--  Performance: GPS writes throttled by distance threshold
-- ============================================================

-- ─── JOIN UNIT ───────────────────────────────────────────────
RegisterNetEvent('kcmdt:joinUnit', function(unitCall)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.spamCheck(src) then return end

    -- Validate unit_call mod config
    local valid = false
    local label = unitCall
    for _, u in ipairs(Config.PatrolUnits) do
        if u.call == unitCall then valid = true; label = u.label; break end
    end
    if not valid then
        TriggerClientEvent('kcmdt:notify', src, 'Ugyldig enhed.', 'error')
        return
    end

    sess.unit = unitCall

    MySQL.query.await([[
        INSERT INTO polititablet_patrol_units (unit_call,label,officer_id,officer_name,status)
        VALUES (?,?,?,?,1)
        ON DUPLICATE KEY UPDATE unit_call=?, label=?, status=1, last_update=NOW()
    ]], { unitCall, label, sess.identifier, sess.rawName, unitCall, label })

    KCS.broadcastPatrolList()
    TriggerClientEvent('kcmdt:notify', src, 'Du er nu i enhed '..unitCall, 'success')
end)

-- ─── SET STATUS ──────────────────────────────────────────────
RegisterNetEvent('kcmdt:setUnitStatus', function(status)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    local s = KC.clampInt(status or 1, 1, 4)
    sess.status = s

    MySQL.update('UPDATE polititablet_patrol_units SET status=? WHERE officer_id=?', { s, sess.identifier })
    KCS.broadcastPatrolList()

    if s == 4 then
        -- Panic — broadcast med koordinater
        local ped = GetPlayerPed(src)
        local cx, cy, cz
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped); cx, cy, cz = c.x, c.y, c.z
        end
        KCS.broadcastMDT('kcmdt:panicAlert', {
            officer    = sess.rawName,
            identifier = sess.identifier,
            unit       = sess.unit,
            coords_x   = cx, coords_y = cy, coords_z = cz,
        })
        KCS.audit(sess.identifier, sess.rawName, 'PANIC', sess.unit or '-', nil)
    end
end)

-- ─── GPS UPDATE (throttled by distance) ──────────────────────
RegisterNetEvent('kcmdt:updateGPS', function(x, y, z)
    local src = source
    local sess = KCS.getSession(src); if not sess then return end
    x = tonumber(x); y = tonumber(y); z = tonumber(z)
    if not x or not y or not z then return end

    -- Lagrer i in-memory cache; skriv kun til DB hvis vi har bevæget os mere end threshold
    local cache = KCS.gpsCache[sess.identifier]
    if cache then
        local dx, dy = x - cache.x, y - cache.y
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist < Config.GPSWriteThreshold and (os.time() - cache.lastWrite) < 30 then
            -- Spring DB-write over; opdater bare in-memory
            cache.x, cache.y, cache.z = x, y, z
            sess.coords = { x = x, y = y, z = z }
            return
        end
    end

    KCS.gpsCache[sess.identifier] = { x = x, y = y, z = z, lastWrite = os.time() }
    sess.coords = { x = x, y = y, z = z }

    MySQL.update(
        'UPDATE polititablet_patrol_units SET coords_x=?, coords_y=?, coords_z=?, last_update=NOW() WHERE officer_id=?',
        { x, y, z, sess.identifier }
    )
end)

-- ─── VEHICLE STATE (Flådestyring §22) ─────────────────────────
-- Sendes af klienten KUN når køretøj/sæde reelt ændrer sig (se
-- cl_polititablet.lua) — ikke et polling-event, så ingen ekstra
-- netværkstrafik ud over selve ændringen.
RegisterNetEvent('kcmdt:updateVehicleState', function(vehicleLabel, vehicleNetId, seatRole)
    local src = source
    local sess = KCS.getSession(src); if not sess then return end

    if vehicleLabel ~= nil and type(vehicleLabel) ~= 'string' then return end
    if vehicleNetId ~= nil and type(vehicleNetId) ~= 'number' then return end
    if seatRole ~= 'driver' and seatRole ~= 'passenger' and seatRole ~= nil then return end

    sess.vehicleLabel = vehicleLabel and KC.safeStr(vehicleLabel, 100) or nil
    sess.vehicleNetId = vehicleNetId
    sess.seatRole      = seatRole

    -- Named parametre: vehicleLabel/vehicleNetId/seatRole er alle nil så
    -- snart betjenten ikke er i et køretøj (det almindelige tilfælde), og
    -- `ipairs` over en positionel array stopper ved det FØRSTE nil-hul —
    -- her ville det være index 1, så en positionel `?`-liste kunne ende
    -- med at sende nul parametre. Named `:key` er upåvirket af det.
    MySQL.update(
        'UPDATE polititablet_patrol_units SET vehicle_label=:vehicleLabel, vehicle_netid=:vehicleNetId, seat_role=:seatRole WHERE officer_id=:officerId',
        { vehicleLabel = sess.vehicleLabel, vehicleNetId = sess.vehicleNetId, seatRole = sess.seatRole, officerId = sess.identifier }
    )

    KCS.broadcastPatrolList()
end)

-- ─── GET PATROL UNITS ────────────────────────────────────────
lib.callback.register('kcmdt:getPatrolUnits', function(src)
    if not KCS.requireSession(src) then return {} end
    -- Vi returnerer in-memory liste (live) — slet ikke længere stale-DB-rows hver query.
    return KCS.getPatrolList()
end)

-- ─── DUTY TIME (sidste 7 dage) ───────────────────────────────
lib.callback.register('kcmdt:getDutyTime', function(src)
    local sess = KCS.requireSession(src); if not sess then return 0 end
    local s = MySQL.scalar.await([[
        SELECT COALESCE(SUM(seconds),0) +
               COALESCE(TIMESTAMPDIFF(SECOND, MAX(CASE WHEN duty_off IS NULL THEN duty_on END), NOW()),0)
        FROM polititablet_duty_log
        WHERE identifier=? AND duty_on >= DATE_SUB(NOW(),INTERVAL 7 DAY)
    ]], { sess.identifier })
    return tonumber(s) or 0
end)

-- ─── STALE PATROL CLEANUP THREAD ─────────────────────────────
CreateThread(function()
    while true do
        Wait(120000) -- hver 2. minut
        MySQL.update(
            ("DELETE FROM polititablet_patrol_units WHERE last_update < DATE_SUB(NOW(), INTERVAL %d SECOND)"):format(Config.PatrolCleanupSec),
            {}
        )
    end
end)
