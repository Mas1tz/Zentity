-- ============================================================
--  Masitz-garage | server/sv_garage.lua
--  Kerne: hente/parkere biler+både, impound, nøgle-gendannelse.
--  Uændret funktionalitet ift. MM-garage/kc_garage — kun omdøbt
--  til masitz_garage:*-events og flyttet til MG.*-hjælpere.
-- ============================================================

local ESX = MG.ESX

-- ═══════════════════════════════════════════════════════════
--  SKIFT BILNAVN (§5) — server-autoritativ, valideret input
-- ═══════════════════════════════════════════════════════════

lib.callback.register('masitz_garage:renameVehicle', function(src, plate, newNameRaw)
    local xp = MG.GetXPlayer(src)
    if not xp then return { success = false, msg = 'Ikke logget ind.' } end

    plate = MG.NormPlate(plate)
    if not plate then return { success = false, msg = 'Ugyldig nummerplade.' } end

    local newName = MG.SafeVehicleName(newNameRaw)
    if not newName then
        return { success = false, msg = 'Ugyldigt navn (tomt, eller kun ugyldige tegn).' }
    end

    local row = MySQL.single.await(
        'SELECT vehicle_name FROM owned_vehicles WHERE owner = ? AND REPLACE(plate," ","") = ? AND impound = 0',
        { xp.identifier, plate }
    )
    if not row then return { success = false, msg = 'Du ejer ikke dette køretøj.' } end

    local changed = MySQL.update.await(
        'UPDATE owned_vehicles SET vehicle_name = ? WHERE owner = ? AND REPLACE(plate," ","") = ?',
        { newName, xp.identifier, plate }
    )

    if not changed or changed < 1 then
        return { success = false, msg = 'Database-fejl. Prøv igen.' }
    end

    MG.LogRename({
        playerName = xp.getName(), identifier = xp.identifier,
        oldName = row.vehicle_name or '(intet)', newName = newName, plate = plate,
    })
    MG.Log(('RENAME: %s omdøbte %s til "%s"'):format(xp.identifier, plate, newName))

    return { success = true, newName = newName }
end)

-- ═══════════════════════════════════════════════════════════
--  CALLBACKS — BILER
-- ═══════════════════════════════════════════════════════════

lib.callback.register('masitz_garage:getVehicles', function(src, garageKey)
    local xp = MG.GetXPlayer(src)
    if not xp then return {} end

    local rows = MySQL.query.await(
        [[SELECT plate, vehicle, vehicle_name, fuel, engine_health, body_health
          FROM   owned_vehicles
          WHERE  owner    = ?
          AND    parking  = ?
          AND    stored   = 1
          AND    impound  = 0
          AND    garage_type = 'car']],
        { xp.identifier, garageKey }
    )

    if not rows or #rows == 0 then return {} end

    local vehicles = {}
    for _, row in ipairs(rows) do
        local ok, data = pcall(json.decode, row.vehicle or '{}')
        if not ok or type(data) ~= 'table' then data = {} end
        table.insert(vehicles, {
            plate        = row.plate,
            model        = data.model or 'unknown',
            vehicleName  = row.vehicle_name,
            fuel         = row.fuel          or Config.DefaultFuel,
            engineHealth = row.engine_health  or Config.DefaultEngine,
            bodyHealth   = row.body_health    or Config.DefaultBody,
        })
    end
    return vehicles
end)

lib.callback.register('masitz_garage:getImpounded', function(src, impoundKey)
    local xp = MG.GetXPlayer(src)
    if not xp then return {} end

    local rows = MySQL.query.await(
        [[SELECT plate, vehicle, vehicle_name, impound_reason, impound_fee, impound_at, impound_location
          FROM   owned_vehicles
          WHERE  owner   = ?
          AND    impound = 1
          AND    (impound_location = ? OR ? IS NULL)]],
        { xp.identifier, impoundKey, impoundKey }
    )

    if not rows or #rows == 0 then return {} end

    local vehicles = {}
    for _, row in ipairs(rows) do
        local ok, data = pcall(json.decode, row.vehicle or '{}')
        if not ok or type(data) ~= 'table' then data = {} end

        local impoundTs = MG.ParseSqlDatetime(row.impound_at)

        table.insert(vehicles, {
            plate       = row.plate,
            model       = data.model or 'unknown',
            vehicleName = row.vehicle_name,
            reason      = row.impound_reason   or 'Ukendt',
            fee         = MG.CalcImpoundFee(impoundTs),
            location    = row.impound_location or impoundKey,
        })
    end
    return vehicles
end)

-- ═══════════════════════════════════════════════════════════
--  CALLBACKS — BÅDE
-- ═══════════════════════════════════════════════════════════

lib.callback.register('masitz_garage:getBoats', function(src, boatKey)
    local xp = MG.GetXPlayer(src)
    if not xp then return {} end

    local rows = MySQL.query.await(
        [[SELECT plate, vehicle, vehicle_name, fuel, engine_health, body_health
          FROM   owned_vehicles
          WHERE  owner       = ?
          AND    parking     = ?
          AND    stored      = 1
          AND    impound     = 0
          AND    garage_type = 'boat']],
        { xp.identifier, boatKey }
    )

    if not rows or #rows == 0 then return {} end

    local vehicles = {}
    for _, row in ipairs(rows) do
        local ok, data = pcall(json.decode, row.vehicle or '{}')
        if not ok or type(data) ~= 'table' then data = {} end
        table.insert(vehicles, {
            plate        = row.plate,
            model        = data.model or 'unknown',
            vehicleName  = row.vehicle_name,
            fuel         = row.fuel          or Config.DefaultFuel,
            engineHealth = row.engine_health  or Config.DefaultEngine,
            bodyHealth   = row.body_health    or Config.DefaultBody,
        })
    end
    return vehicles
end)

-- ═══════════════════════════════════════════════════════════
--  ANDRE GEMTE KØRETØJER (til "Flyt bil" / "Hent bil hertil") —
--  se sv_transfer.lua, som kalder denne.
-- ═══════════════════════════════════════════════════════════

-- Returnerer spillerens ØVRIGE lagrede (ikke-impounded) køretøjer af en
-- given type, som IKKE allerede står i excludeGarageKey.
function MG.GetOtherStoredVehicles(identifier, garageType, excludeGarageKey)
    local rows = MySQL.query.await(
        [[SELECT plate, vehicle, vehicle_name, parking
          FROM   owned_vehicles
          WHERE  owner       = ?
          AND    stored      = 1
          AND    impound     = 0
          AND    garage_type = ?
          AND    parking     != ?]],
        { identifier, garageType, excludeGarageKey or '' }
    ) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local ok, data = pcall(json.decode, row.vehicle or '{}')
        if not ok or type(data) ~= 'table' then data = {} end
        out[#out + 1] = {
            plate       = row.plate,
            model       = data.model or 'unknown',
            vehicleName = row.vehicle_name,
            parking     = row.parking,
        }
    end
    return out
end

-- ═══════════════════════════════════════════════════════════
--  STORE VEHICLE (bil)
-- ═══════════════════════════════════════════════════════════

RegisterNetEvent('masitz_garage:storeVehicle', function(plate, garageKey, props, netId)
    local src = source
    local xp  = MG.GetXPlayer(src)
    if not xp then return end

    plate     = MG.NormPlate(plate)
    garageKey = tostring(garageKey or '')

    if not plate or not Config.Garages[garageKey] then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Ugyldig garage eller plade.' })
        return
    end

    if type(props) ~= 'table' then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Køretøjsdata mangler.' })
        return
    end

    local owned = MySQL.scalar.await(
        'SELECT 1 FROM owned_vehicles WHERE owner = ? AND UPPER(REPLACE(plate," ","")) = ? AND impound = 0 AND garage_type = \'car\'',
        { xp.identifier, plate }
    )

    if not owned then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Du ejer ikke dette køretøj.' })
        return
    end

    local fuel   = math.max(0.0, math.min(100.0,  tonumber(props.fuelLevel)    or Config.DefaultFuel))
    local engine = math.max(0.0, math.min(1000.0, tonumber(props.engineHealth) or Config.DefaultEngine))
    local body   = math.max(0.0, math.min(1000.0, tonumber(props.bodyHealth)   or Config.DefaultBody))

    props.fuelLevel    = fuel
    props.engineHealth = engine
    props.bodyHealth   = body

    local changed = MySQL.update.await(
        [[UPDATE owned_vehicles
          SET    stored        = 1,
                 parking       = ?,
                 last_garage   = ?,
                 vehicle       = ?,
                 fuel          = ?,
                 engine_health = ?,
                 body_health   = ?
          WHERE  owner                    = ?
          AND    REPLACE(plate," ","")    = ?
          AND    impound                  = 0
          AND    garage_type              = 'car']],
        { garageKey, garageKey, json.encode(props), fuel, engine, body, xp.identifier, plate }
    )

    if changed and changed > 0 then
        TriggerClientEvent('masitz_garage:dvVehicle', src, netId)
        TriggerClientEvent('ox_lib:notify', src, {
            type='success', description='Bil parkeret i ' .. (Config.Garages[garageKey].label or garageKey)
        })
        MG.LogVehicleStored({
            playerName = xp.getName(), identifier = xp.identifier,
            vehicleLabel = props.model, plate = plate,
            garageLabel = Config.Garages[garageKey].label or garageKey,
        })
        MG.Log(('STORE: %s parkerede %s i %s'):format(xp.identifier, plate, garageKey))
    else
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Kunne ikke gemme køretøjet.' })
    end
end)

-- ═══════════════════════════════════════════════════════════
--  STORE BOAT
-- ═══════════════════════════════════════════════════════════

RegisterNetEvent('masitz_garage:storeBoat', function(plate, boatKey, props, netId)
    local src = source
    local xp  = MG.GetXPlayer(src)
    if not xp then return end

    plate   = MG.NormPlate(plate)
    boatKey = tostring(boatKey or '')

    if not plate or not Config.Boat[boatKey] then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Ugyldig marina eller plade.' })
        return
    end

    if type(props) ~= 'table' then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Fartøjsdata mangler.' })
        return
    end

    local owned = MySQL.scalar.await(
        'SELECT 1 FROM owned_vehicles WHERE owner = ? AND UPPER(REPLACE(plate," ","")) = ? AND impound = 0 AND garage_type = \'boat\'',
        { xp.identifier, plate }
    )

    if not owned then
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Du ejer ikke denne båd.' })
        return
    end

    local fuel   = math.max(0.0, math.min(100.0,  tonumber(props.fuelLevel)    or Config.DefaultFuel))
    local engine = math.max(0.0, math.min(1000.0, tonumber(props.engineHealth) or Config.DefaultEngine))
    local body   = math.max(0.0, math.min(1000.0, tonumber(props.bodyHealth)   or Config.DefaultBody))

    props.fuelLevel    = fuel
    props.engineHealth = engine
    props.bodyHealth   = body

    local changed = MySQL.update.await(
        [[UPDATE owned_vehicles
          SET    stored        = 1,
                 parking       = ?,
                 last_garage   = ?,
                 vehicle       = ?,
                 fuel          = ?,
                 engine_health = ?,
                 body_health   = ?
          WHERE  owner                    = ?
          AND    REPLACE(plate," ","")    = ?
          AND    impound                  = 0
          AND    garage_type              = 'boat']],
        { boatKey, boatKey, json.encode(props), fuel, engine, body, xp.identifier, plate }
    )

    if changed and changed > 0 then
        TriggerClientEvent('masitz_garage:dvVehicle', src, netId)
        TriggerClientEvent('ox_lib:notify', src, {
            type='success', description='Båd fortøjet i ' .. (Config.Boat[boatKey].label or boatKey)
        })
        MG.LogVehicleStored({
            playerName = xp.getName(), identifier = xp.identifier,
            vehicleLabel = props.model, plate = plate,
            garageLabel = Config.Boat[boatKey].label or boatKey,
        })
        MG.Log(('STORE BOAT: %s fortøjede %s i %s'):format(xp.identifier, plate, boatKey))
    else
        TriggerClientEvent('ox_lib:notify', src, { type='error', description='Kunne ikke gemme båden.' })
    end
end)

-- ═══════════════════════════════════════════════════════════
--  SPAWN VEHICLE (bil)
-- ═══════════════════════════════════════════════════════════

lib.callback.register('masitz_garage:spawnVehicle', function(src, plate, garageKey)
    local xp = MG.GetXPlayer(src)
    if not xp then return nil end

    plate     = MG.NormPlate(plate)
    garageKey = tostring(garageKey or '')

    if not plate or not Config.Garages[garageKey] then return nil end

    local row = MySQL.single.await(
        [[SELECT vehicle, fuel, engine_health, body_health
          FROM   owned_vehicles
          WHERE  owner                    = ?
          AND    REPLACE(plate," ","")    = ?
          AND    parking                  = ?
          AND    stored                   = 1
          AND    impound                  = 0
          AND    garage_type              = 'car']],
        { xp.identifier, plate, garageKey }
    )

    if not row then
        MG.Log(('SPAWN DENY: %s forsøgte at hente %s fra %s'):format(xp.identifier, plate, garageKey))
        return nil
    end

    local updated = MySQL.update.await(
        [[UPDATE owned_vehicles
          SET    stored = 0
          WHERE  owner                    = ?
          AND    REPLACE(plate," ","")    = ?
          AND    parking                  = ?
          AND    stored                   = 1
          AND    impound                  = 0
          AND    garage_type              = 'car']],
        { xp.identifier, plate, garageKey }
    )

    if not updated or updated < 1 then return nil end

    local ok, props = pcall(json.decode, row.vehicle or '{}')
    if not ok or type(props) ~= 'table' then props = {} end

    props.fuelLevel    = row.fuel          or props.fuelLevel    or Config.DefaultFuel
    props.engineHealth = row.engine_health or props.engineHealth or Config.DefaultEngine
    props.bodyHealth   = row.body_health   or props.bodyHealth   or Config.DefaultBody

    TriggerEvent('masitz_garage:giveKey', src, plate)
    MG.LogVehicleRetrieved({
        playerName = xp.getName(), identifier = xp.identifier,
        vehicleLabel = props.model, plate = plate,
        garageLabel = Config.Garages[garageKey].label or garageKey,
    })
    MG.Log(('SPAWN: %s henter %s fra %s'):format(xp.identifier, plate, garageKey))

    return { props=props, spawnCoords=Config.Garages[garageKey].spawn }
end)

-- ═══════════════════════════════════════════════════════════
--  SPAWN BOAT
-- ═══════════════════════════════════════════════════════════

lib.callback.register('masitz_garage:spawnBoat', function(src, plate, boatKey)
    local xp = MG.GetXPlayer(src)
    if not xp then return nil end

    plate   = MG.NormPlate(plate)
    boatKey = tostring(boatKey or '')

    if not plate or not Config.Boat[boatKey] then return nil end

    local row = MySQL.single.await(
        [[SELECT vehicle, fuel, engine_health, body_health
          FROM   owned_vehicles
          WHERE  owner                    = ?
          AND    REPLACE(plate," ","")    = ?
          AND    parking                  = ?
          AND    stored                   = 1
          AND    impound                  = 0
          AND    garage_type              = 'boat']],
        { xp.identifier, plate, boatKey }
    )

    if not row then
        MG.Log(('SPAWN BOAT DENY: %s forsøgte at hente %s fra %s'):format(xp.identifier, plate, boatKey))
        return nil
    end

    local updated = MySQL.update.await(
        [[UPDATE owned_vehicles
          SET    stored = 0
          WHERE  owner                    = ?
          AND    REPLACE(plate," ","")    = ?
          AND    parking                  = ?
          AND    stored                   = 1
          AND    impound                  = 0
          AND    garage_type              = 'boat']],
        { xp.identifier, plate, boatKey }
    )

    if not updated or updated < 1 then return nil end

    local ok, props = pcall(json.decode, row.vehicle or '{}')
    if not ok or type(props) ~= 'table' then props = {} end

    props.fuelLevel    = row.fuel          or props.fuelLevel    or Config.DefaultFuel
    props.engineHealth = row.engine_health or props.engineHealth or Config.DefaultEngine
    props.bodyHealth   = row.body_health   or props.bodyHealth   or Config.DefaultBody

    TriggerEvent('masitz_garage:giveKey', src, plate)
    MG.LogVehicleRetrieved({
        playerName = xp.getName(), identifier = xp.identifier,
        vehicleLabel = props.model, plate = plate,
        garageLabel = Config.Boat[boatKey].label or boatKey,
    })
    MG.Log(('SPAWN BOAT: %s henter %s fra %s'):format(xp.identifier, plate, boatKey))

    return { props=props, spawnCoords=Config.Boat[boatKey].spawn }
end)

-- ═══════════════════════════════════════════════════════════
--  IMPOUND
-- ═══════════════════════════════════════════════════════════

function MG.ImpoundVehicle(plate, reason, impoundKey)
    plate      = MG.NormPlate(plate)
    impoundKey = impoundKey or 'innocence'
    reason     = reason or 'Ikke specificeret'

    if not plate then return false end

    if not Config.Impounds[impoundKey] then
        for k in pairs(Config.Impounds) do impoundKey = k; break end
    end

    local baseFee = Config.ImpoundBaseFee

    local ownerRow = MySQL.single.await(
        'SELECT owner FROM owned_vehicles WHERE REPLACE(plate," ","") = ? AND impound = 0',
        { plate }
    )

    local changed = MySQL.update.await(
        [[UPDATE owned_vehicles
          SET    stored           = 1,
                 impound          = 1,
                 impound_location = ?,
                 impound_reason   = ?,
                 impound_fee      = ?,
                 impound_at       = NOW(),
                 parking          = ?
          WHERE  REPLACE(plate," ","") = ?
          AND    impound = 0]],
        { impoundKey, reason, baseFee, impoundKey, plate }
    )

    if changed and changed > 0 then
        MySQL.insert.await(
            [[INSERT INTO impound_log (plate, owner, location, reason, fee)
              SELECT REPLACE(plate," ",""), owner, ?, ?, ?
              FROM   owned_vehicles
              WHERE  REPLACE(plate," ","") = ?]],
            { impoundKey, reason, baseFee, plate }
        )
        MG.LogImpound({
            plate = plate, owner = ownerRow and ownerRow.owner or '?',
            location = (Config.Impounds[impoundKey] and Config.Impounds[impoundKey].label) or impoundKey,
            reason = reason, fee = baseFee,
        })
        MG.Log(('IMPOUND: %s → %s (%s)'):format(plate, impoundKey, reason))
        return true
    end
    return false
end

-- Bagudkompatibelt alias — et eksternt script (skade-/crash-detektion
-- e.l.) kan allerede kalde det gamle event-navn. Begge navne rammer
-- samme logik, så intet eksternt script går i stykker ved omdøbningen.
local function OnVehicleDestroyed(plate, reason)
    if not Config.ImpoundEnabled then return end
    MG.ImpoundVehicle(plate, reason or 'Køretøj ødelagt', 'innocence')
end
AddEventHandler('masitz_garage:vehicleDestroyed', OnVehicleDestroyed)
AddEventHandler('garage:vehicleDestroyed', OnVehicleDestroyed)

lib.callback.register('masitz_garage:releaseImpound', function(src, plate, impoundKey)
    local xp = MG.GetXPlayer(src)
    if not xp then return { success=false, msg='Ikke logget ind' } end

    plate      = MG.NormPlate(plate)
    impoundKey = tostring(impoundKey or '')

    if not plate or not Config.Impounds[impoundKey] then
        return { success=false, msg='Ugyldig impound eller plade.' }
    end

    local row = MySQL.single.await(
        [[SELECT impound_at, impound_fee
          FROM   owned_vehicles
          WHERE  owner                    = ?
          AND    REPLACE(plate," ","")    = ?
          AND    impound                  = 1
          AND    impound_location         = ?]],
        { xp.identifier, plate, impoundKey }
    )

    if not row then return { success=false, msg='Bilen er ikke på dette impound.' } end

    local impoundTs = MG.ParseSqlDatetime(row.impound_at)
    local fee = MG.CalcImpoundFee(impoundTs)

    if not MG.TryCharge(xp, 'money', fee) then
        return {
            success = false,
            msg     = ('Du mangler penge til gebyret (%s).'):format(MG.FormatMoney(fee))
        }
    end

    local changed = MySQL.update.await(
        [[UPDATE owned_vehicles
          SET    impound          = 0,
                 impound_location = NULL,
                 impound_reason   = NULL,
                 impound_fee      = 0,
                 impound_at       = NULL,
                 stored           = 1,
                 parking          = last_garage
          WHERE  owner                    = ?
          AND    REPLACE(plate," ","")    = ?
          AND    impound                  = 1]],
        { xp.identifier, plate }
    )

    if changed and changed > 0 then
        MySQL.update.await(
            'UPDATE impound_log SET paid=1, released_at=NOW() WHERE plate=? AND paid=0 ORDER BY id DESC LIMIT 1',
            { plate }
        )
        MG.LogImpoundRelease({ playerName = xp.getName(), identifier = xp.identifier, plate = plate, fee = fee })
        MG.Log(('RELEASE: %s betalte %d kr. for %s'):format(xp.identifier, fee, plate))
        return { success=true, fee=fee }
    end

    -- Database-opdateringen fejlede efter betaling blev trukket — rul tilbage.
    MG.Pay(xp, 'money', fee)
    return { success=false, msg='Database fejl. Prøv igen.' }
end)

-- ═══════════════════════════════════════════════════════════
--  KEY SYSTEM (spillerens EGET nøgle ved spawn/gendannelse) —
--  "Giv nøgler til en anden spiller" ligger i sv_keys.lua.
-- ═══════════════════════════════════════════════════════════

AddEventHandler('masitz_garage:giveKey', function(src, plate)
    if not Config.KeySystem then return end
    local xp = MG.GetXPlayer(src)
    if not xp then return end
    plate = MG.NormPlate(plate)
    if not plate then return end

    local ok, err = pcall(function()
        exports[Config.KeyExport]:Masitz_giveKey(src, plate)
    end)
    if not ok then MG.Log('KeySystem giveKey fejl: ' .. tostring(err)) end

    MySQL.query.await(
        'INSERT IGNORE INTO vehicle_keys (identifier, plate) VALUES (?, ?)',
        { xp.identifier, plate }
    )
end)

AddEventHandler('esx:playerLoaded', function(src)
    if not Config.KeySystem then return end
    Wait(2000)
    MG.RestoreKeys(src)
end)

function MG.RestoreKeys(src)
    local xp = MG.GetXPlayer(src)
    if not xp then return end

    local rows = MySQL.query.await(
        'SELECT plate FROM vehicle_keys WHERE identifier = ?',
        { xp.identifier }
    )
    if not rows or #rows == 0 then return end

    for _, row in ipairs(rows) do
        local ok, err = pcall(function()
            exports[Config.KeyExport]:Masitz_giveKey(src, row.plate)
        end)
        if not ok then MG.Log('RestoreKeys fejl: ' .. tostring(err)) end
    end
    MG.Log(('KEYS: Gendannet %d nøgler for %s'):format(#rows, xp.identifier))
end

RegisterNetEvent('masitz_garage:removeKey', function(plate)
    local src = source
    local xp  = MG.GetXPlayer(src)
    if not xp then return end
    plate = MG.NormPlate(plate)
    if not plate then return end

    pcall(function()
        exports[Config.KeyExport]:Masitz_removeKey(src, plate)
    end)
    MySQL.query.await(
        'DELETE FROM vehicle_keys WHERE identifier = ? AND plate = ?',
        { xp.identifier, plate }
    )
end)

-- ═══════════════════════════════════════════════════════════
--  RESOURCE START
-- ═══════════════════════════════════════════════════════════

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1000)
    local fixed = MySQL.update.await(
        [[UPDATE owned_vehicles
          SET   stored  = 1,
                parking = last_garage
          WHERE stored  = 0
          AND   impound = 0]],
        {}
    )
    MG.Log(('RESTART: %d køretøjer returneret til last_garage'):format(fixed or 0))
end)
