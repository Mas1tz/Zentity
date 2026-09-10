-- ============================================================
--  kc_mdt | server/sv_vehicles.lua
--  Vehicle records, traffic stops, plate lookup
-- ============================================================

-- ═══════════════════════════════════════════════════════════
--  SEARCH VEHICLE BY PLATE
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:searchVehicle', function(src, plate)
    if not KCS.requireSession(src) then return { found=false } end
    plate = KC.normPlate(plate)
    if not plate or #plate < 2 then return { found=false } end

    -- ESX Legacy: owned_vehicles tabel (lookup uden trailing space-padding)
    local row = MySQL.single.await([[
        SELECT ov.plate, ov.vehicle, ov.owner, ov.stored, ov.job,
               u.firstname, u.lastname, u.identifier AS ownerCitizenId
        FROM owned_vehicles ov
        LEFT JOIN users u ON u.identifier = ov.owner
        WHERE REPLACE(UPPER(ov.plate),' ','') = ?
        LIMIT 1
    ]], { plate })

    if not row then return { found=false } end

    -- Hent flags fra polititablet_vehicle_records
    local rec = MySQL.single.await('SELECT * FROM polititablet_vehicle_records WHERE plate=?', { plate })
    -- Trafikstops (sidste 20)
    local stops = MySQL.query.await([[
        SELECT id, officer_name, notes, created_at
        FROM polititablet_traffic_stops
        WHERE plate=?
        ORDER BY created_at DESC
        LIMIT 20
    ]], { plate }) or {}

    -- Parse vehicle properties (kan være JSON-string i ESX Legacy)
    local props = nil
    if row.vehicle then
        local ok, parsed = pcall(json.decode, row.vehicle)
        if ok and type(parsed) == 'table' then props = parsed end
    end

    return {
        found          = true,
        plate          = plate,
        ownerCitizenId = row.ownerCitizenId or row.owner,
        owner          = (row.firstname and (row.firstname..' '..row.lastname)) or 'Ukendt',
        stored         = row.stored == 1,
        job            = row.job,
        props          = props,
        flags = rec and {
            stolen    = rec.stolen == 1,
            seized    = rec.seized == 1,
            bolo      = rec.bolo == 1,
            tracker   = rec.tracker == 1,
            insurance = rec.insurance == 1,
            notes     = rec.notes or '',
        } or {
            stolen=false, seized=false, bolo=false, tracker=false, insurance=true, notes=''
        },
        stops = stops,
    }
end)

-- ═══════════════════════════════════════════════════════════
--  SEARCH VEHICLES — DELVIS NUMMERPLADE (§21)
--  Den oprindelige searchVehicle ovenfor kræver en EKSAKT plade.
--  Denne understøtter delvis søgning ("ABC" -> ABC123, ABC555, XABC22, ...)
--  og returnerer en let liste, som klienten kan klikke sig videre fra ind
--  i searchVehicle for de fulde detaljer.
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:searchVehiclesList', function(src, query)
    if not KCS.requireSession(src) then return {} end
    query = KC.trim(query or ''):upper():gsub('%s+', '')
    if #query < 2 then return {} end
    local needle = '%' .. query .. '%'

    local rows = MySQL.query.await([[
        SELECT ov.plate, ov.vehicle, ov.stored,
               u.firstname, u.lastname,
               (SELECT COUNT(*) FROM polititablet_vehicle_records r
                WHERE r.plate = ov.plate AND (r.stolen = 1 OR r.bolo = 1)) AS flagged
        FROM owned_vehicles ov
        LEFT JOIN users u ON u.identifier = ov.owner
        WHERE REPLACE(UPPER(ov.plate), ' ', '') LIKE ?
        ORDER BY ov.plate
        LIMIT 25
    ]], { needle }) or {}

    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            plate      = row.plate,
            owner      = (row.firstname and (row.firstname .. ' ' .. row.lastname)) or 'Ukendt',
            vehicleRaw = row.vehicle,
            stored     = row.stored == 1,
            flagged    = (row.flagged or 0) > 0,
        }
    end
    return out
end)

-- ═══════════════════════════════════════════════════════════
--  UPDATE VEHICLE RECORD (flags)
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('kcmdt:updateVehicleRecord', function(plate, flags)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.requirePermission(src, 'flagVehicle') then return end
    if not KCS.spamCheck(src) then return end

    plate = KC.normPlate(plate); if not plate then return end
    if type(flags) ~= 'table' then return end

    local stolen    = flags.stolen    and 1 or 0
    local seized    = flags.seized    and 1 or 0
    local bolo      = flags.bolo      and 1 or 0
    local tracker   = flags.tracker   and 1 or 0
    local insurance = flags.insurance and 1 or 0
    local notes     = KC.safeStr(flags.notes or '', 2000)

    MySQL.query.await([[
        INSERT INTO polititablet_vehicle_records (plate,stolen,seized,bolo,tracker,insurance,notes)
        VALUES (?,?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE stolen=?, seized=?, bolo=?, tracker=?, insurance=?, notes=?
    ]], { plate, stolen, seized, bolo, tracker, insurance, notes,
          stolen, seized, bolo, tracker, insurance, notes })

    KCS.audit(sess.identifier, sess.rawName, 'UPDATE_VEHICLE', plate,
        ('st=%d sz=%d bolo=%d trk=%d ins=%d'):format(stolen, seized, bolo, tracker, insurance))
    TriggerClientEvent('kcmdt:notify', src, 'Køretøjsregister opdateret.', 'success')
end)

-- ═══════════════════════════════════════════════════════════
--  TRAFFIC STOPS
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('kcmdt:addTrafficStop', function(plate, notes)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.spamCheck(src) then return end

    plate = KC.normPlate(plate); if not plate then return end
    notes = KC.safeStr(notes or '', 1000)

    MySQL.insert('INSERT INTO polititablet_traffic_stops (plate,officer_id,officer_name,notes) VALUES (?,?,?,?)',
        { plate, sess.identifier, sess.rawName, notes })
    KCS.audit(sess.identifier, sess.rawName, 'TRAFFIC_STOP', plate, notes:sub(1, 100))
    TriggerClientEvent('kcmdt:notify', src, 'Standsning registreret.', 'success')
end)
