-- ============================================================
--  Masitz-AgriHub | server/tasks.lua
--  GENERISK task-engine — én motor for diesel/gødning/kemikalie/
--  redskab/dyretransport/maskine-til-NPC (§44, §71-§73, §86).
--
--  Data-skema (agrihub_tasks.data, JSON):
--  { stops = [ { coords={x,y,z}, done=bool, meta={...} }, ... ],
--    meta  = { ...type-specifik visningsinfo... } }
--  Al position-/køretøjsvalidering foregår SERVER-SIDE ud fra
--  stops[].coords — klienten kan aldrig selv erklære et stop fuldført.
-- ============================================================

AH = AH or {}

local function PickRandom(t)
    if #t == 0 then return nil end
    return t[math.random(1, #t)]
end

local function ShuffleCopy(t)
    local out = {}
    for i, v in ipairs(t) do out[i] = v end
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

local function FarmersWithTask(taskType)
    local out = {}
    for _, f in ipairs(Config.Agri.Farmers) do
        for _, t in ipairs(f.tasks) do
            if t == taskType then out[#out + 1] = f; break end
        end
    end
    return out
end

-- ─── VEHICLE-GRUPPER (bruges til server-side validering) ──────────
local function VehicleAllowedForGroup(model, group)
    if group == 'rental' then
        for key in pairs(Config.Agri.Rentals) do
            if GetHashKey(key) == model then return true end
        end
        return false
    end

    local list
    if group == 'delivery' then list = Config.Agri.DeliveryVehicles
    elseif group == 'diesel' then list = Config.Agri.Diesel.trucks
    elseif group == 'equipment' then list = { Config.Agri.Equipment.towVehicle }
    elseif group == 'animals' then list = { Config.Agri.Animals.vehicle }
    end

    if not list then return true end
    for _, m in ipairs(list) do
        if GetHashKey(m) == model then return true end
    end
    return false
end

-- ─── TASK-GENERERING (§47 — randomiseret, men altid server-valideret) ──
function AH.GenerateTask(taskType)
    local typeCfg = Config.Agri.TaskTypes[taskType]
    if not typeCfg then return nil end

    local stops, reward, meta = {}, 0, {}

    if taskType == 'diesel' then
        local farmers = FarmersWithTask('diesel')
        if #farmers == 0 then return nil end
        local maxStops = math.min(Config.Agri.Diesel.route.maxStops, #farmers)
        if maxStops < Config.Agri.Diesel.route.minStops then maxStops = Config.Agri.Diesel.route.minStops end
        local n = math.random(Config.Agri.Diesel.route.minStops, maxStops)
        local pool = ShuffleCopy(farmers)
        for i = 1, math.min(n, #pool) do
            local f = pool[i]
            stops[#stops + 1] = {
                coords = { x = f.coords.x, y = f.coords.y, z = f.coords.z }, done = false,
                meta = { farmerId = f.id, farmerName = f.name },
            }
        end
        if #stops == 0 then return nil end
        reward = Config.Agri.Diesel.baseReward + (Config.Agri.Diesel.rewardPerStop * #stops)
        meta = { trailerModel = PickRandom(Config.Agri.Diesel.trailerModels), stopCount = #stops }

    elseif taskType == 'fertilizer_delivery' or taskType == 'pesticide_delivery' then
        local itemKey = typeCfg.item
        local farmers = {}
        for _, f in ipairs(Config.Agri.Farmers) do
            for _, b in ipairs(f.buys) do
                if b == itemKey then farmers[#farmers + 1] = f; break end
            end
        end
        local f = PickRandom(farmers)
        if not f then return nil end
        local qty = math.random(typeCfg.minUnits, typeCfg.maxUnits)
        stops[1] = {
            coords = { x = f.coords.x, y = f.coords.y, z = f.coords.z }, done = false,
            meta = { farmerId = f.id, farmerName = f.name, item = itemKey, qty = qty },
        }
        reward = typeCfg.rewardPerUnit * qty
        meta = { item = itemKey, qty = qty, farmerName = f.name }

    elseif taskType == 'equipment_delivery' then
        local farmers = FarmersWithTask('equipment_delivery')
        local f = PickRandom(farmers)
        if not f then return nil end
        local trailer = PickRandom(Config.Agri.Equipment.trailers)
        stops[1] = {
            coords = { x = f.coords.x, y = f.coords.y, z = f.coords.z }, done = false,
            meta = { farmerId = f.id, farmerName = f.name, trailer = trailer },
        }
        reward = math.random(Config.Agri.Equipment.reward.min, Config.Agri.Equipment.reward.max)
        meta = { trailer = trailer, farmerName = f.name }

    elseif taskType == 'animal_transport' then
        local farmers = FarmersWithTask('animal_transport')
        local candidateSources = {}
        for _, f in ipairs(farmers) do
            if #f.animalTypes > 0 then candidateSources[#candidateSources + 1] = f end
        end
        local source = PickRandom(candidateSources)
        if not source then return nil end
        local animalType = PickRandom(source.animalTypes)

        local destOptions = {}
        for _, f in ipairs(Config.Agri.Farmers) do
            if f.id ~= source.id then
                for _, at in ipairs(f.animalTypes) do
                    if at == animalType then
                        destOptions[#destOptions + 1] = { label = f.name, coords = f.coords }
                        break
                    end
                end
            end
        end
        for _, d in ipairs(Config.Agri.AnimalDestinations) do
            destOptions[#destOptions + 1] = { label = d.label, coords = d.coords }
        end
        local dest = PickRandom(destOptions)
        if not dest then return nil end

        stops[1] = {
            coords = { x = source.coords.x, y = source.coords.y, z = source.coords.z }, done = false,
            meta = { stage = 'pickup', farmerId = source.id, farmerName = source.name, animalType = animalType },
        }
        stops[2] = {
            coords = { x = dest.coords.x, y = dest.coords.y, z = dest.coords.z }, done = false,
            meta = { stage = 'dropoff', destLabel = dest.label },
        }
        reward = math.random(Config.Agri.Animals.reward.min, Config.Agri.Animals.reward.max)
        meta = { animalType = animalType, sourceFarmer = source.name, destLabel = dest.label }

    elseif taskType == 'machinery_npc' then
        local farmers = FarmersWithTask('machinery_npc')
        local valid = {}
        for _, f in ipairs(farmers) do
            for _, m in ipairs(f.machines) do
                local rc = Config.Agri.Rentals[m]
                if rc and (not rc.winterOnly or Config.Agri.IsWinter) then
                    valid[#valid + 1] = { farmer = f, machine = m }
                end
            end
        end
        local pick = PickRandom(valid)
        if not pick then return nil end
        local rc = Config.Agri.Rentals[pick.machine]
        stops[1] = {
            coords = { x = pick.farmer.coords.x, y = pick.farmer.coords.y, z = pick.farmer.coords.z }, done = false,
            meta = { farmerId = pick.farmer.id, farmerName = pick.farmer.name, machine = pick.machine },
        }
        reward = math.floor(rc.rent * 0.6)
        meta = { machine = pick.machine, machineLabel = rc.label, farmerName = pick.farmer.name }
    else
        return nil
    end

    local taskId = nil
    for _ = 1, 5 do
        local candidate = AH.GenerateId('AGR')
        local exists = MySQL.scalar.await('SELECT 1 FROM agrihub_tasks WHERE task_id = ?', { candidate })
        if not exists then taskId = candidate; break end
    end
    if not taskId then return nil end

    local expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + typeCfg.expirySec)
    MySQL.insert.await(
        'INSERT INTO agrihub_tasks (task_id, type, player_identifier, data, reward, status, expires_at) VALUES (?, ?, NULL, ?, ?, "available", ?)',
        { taskId, taskType, json.encode({ stops = stops, meta = meta }), reward, expiresAt }
    )

    -- Bevidst INGEN notify-broadcast her — nye opgaver dukker op i listen
    -- næste gang spilleren selv åbner Opgaver-fanen, uden at spamme alle
    -- online spillere med en besked hver gang puljen fyldes op.
    return taskId
end

-- Samlet loft (Config.Agri.TaskPool.maxTotal) på tværs af ALLE typer,
-- genopfyldt langsomt over tid (regenIntervalSec) i stedet for at spawne
-- hele puljen på én gang. Kun tjekket når en spiller rent faktisk åbner
-- opgave-listen — ingen baggrunds-loop.
local lastGeneratedAt = 0

local function EnsureTaskPool()
    local availableCount = MySQL.scalar.await(
        'SELECT COUNT(*) FROM agrihub_tasks WHERE status = "available" AND (expires_at IS NULL OR expires_at > NOW())', {}
    ) or 0
    if availableCount >= Config.Agri.TaskPool.maxTotal then return end

    local types = {}
    for taskType in pairs(Config.Agri.TaskTypes) do types[#types + 1] = taskType end

    if availableCount == 0 then
        -- Puljen er helt tom (fx en frisk installation) — fyld den op med
        -- det samme i stedet for at spillerne skal vente på trickle-in.
        local pool = ShuffleCopy(types)
        local generated = 0
        for _, taskType in ipairs(pool) do
            if generated >= Config.Agri.TaskPool.maxTotal then break end
            if AH.GenerateTask(taskType) then generated = generated + 1 end
        end
        lastGeneratedAt = os.time()
        return
    end

    local now = os.time()
    if lastGeneratedAt ~= 0 and (now - lastGeneratedAt) < Config.Agri.TaskPool.regenIntervalSec then
        return -- der er ikke gået nok tid siden sidste nye opgave
    end

    local pool = ShuffleCopy(types)
    for _, taskType in ipairs(pool) do
        if AH.GenerateTask(taskType) then
            lastGeneratedAt = now
            break
        end
    end
end

-- ─── LISTE (§44, §46) ───────────────────────────────────────────
lib.callback.register('masitz_agrihub:tasks:list', function(src)
    local session = AH.RequireSession(src)
    if not session then return { available = {}, active = {} } end

    -- Lazy expiry — sker kun når en spiller rent faktisk henter listen,
    -- ingen baggrunds-loop nødvendig (§56, §92).
    MySQL.update('UPDATE agrihub_tasks SET status = "expired" WHERE status = "available" AND expires_at IS NOT NULL AND expires_at <= NOW()', {})

    if Config.Agri.TaskPool.generateOnNuiOpen then
        EnsureTaskPool()
    end

    local available = MySQL.query.await(
        'SELECT task_id, type, data, reward, expires_at FROM agrihub_tasks WHERE status = "available" ORDER BY created_at DESC', {}
    ) or {}
    local active = MySQL.query.await(
        'SELECT task_id, type, data, reward, claimed_at FROM agrihub_tasks WHERE status = "active" AND player_identifier = ?', { session.identifier }
    ) or {}

    return { available = available, active = active }
end)

-- ─── CLAIM (§72 — reserveret til ÉN spiller) ────────────────────
lib.callback.register('masitz_agrihub:tasks:claim', function(src, taskId)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Ikke logget ind.' } end

    taskId = tostring(taskId or '')
    -- Atomisk claim: kun ÉN spiller kan vinde WHERE status="available".
    local changed = MySQL.update.await(
        'UPDATE agrihub_tasks SET status = "active", player_identifier = ?, claimed_at = NOW() WHERE task_id = ? AND status = "available"',
        { session.identifier, taskId }
    )
    if not changed or changed < 1 then
        return { success = false, msg = 'Opgaven er ikke længere tilgængelig.' }
    end

    local row = MySQL.single.await('SELECT task_id, type, data, reward FROM agrihub_tasks WHERE task_id = ?', { taskId })
    if not row then return { success = false, msg = 'Fejl ved indlæsning af opgave.' } end

    AH.LogAction('deliveries', 'TASK_CLAIMED', src, { taskId = taskId, type = row.type })
    return { success = true, task = row }
end)

-- ─── FREMGANG PR. STOP (§19, §23, §40, §42 — server valid­erer
--     position + køretøj, aldrig kun klientens ord for det) ──────
lib.callback.register('masitz_agrihub:tasks:reachStop', function(src, taskId, stopIndex)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Ikke logget ind.' } end

    taskId = tostring(taskId or '')
    stopIndex = tonumber(stopIndex)

    local row = MySQL.single.await('SELECT type, data, reward, player_identifier, status FROM agrihub_tasks WHERE task_id = ?', { taskId })
    if not row or row.status ~= 'active' or row.player_identifier ~= session.identifier then
        AH.LogSecurity(src, 'invalid_task_stop', 'Forsøgte at fremme en opgave der ikke er deres/aktiv.', { taskId = taskId })
        return { success = false, msg = 'Ugyldig opgave.' }
    end

    local ok, data = pcall(json.decode, row.data)
    if not ok or type(data) ~= 'table' or type(data.stops) ~= 'table' then
        return { success = false, msg = 'Opgavedata korrupt.' }
    end

    local expectedIndex = nil
    for i, stop in ipairs(data.stops) do
        if not stop.done then expectedIndex = i; break end
    end
    if not expectedIndex or expectedIndex ~= stopIndex then
        return { success = false, msg = 'Forkert rækkefølge på destinationer.' }
    end

    local stop = data.stops[expectedIndex]
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { success = false, msg = 'Spillerdata ikke fundet.' } end

    local coords = GetEntityCoords(ped)
    local dist = #(vector3(coords.x, coords.y, coords.z) - vector3(stop.coords.x, stop.coords.y, stop.coords.z))
    if dist > 15.0 then
        AH.LogSecurity(src, 'task_position_mismatch', 'Forsøgte at fuldføre et stop for langt fra destinationen.', { taskId = taskId, distance = math.floor(dist) })
        return { success = false, msg = 'Du er ikke ved den rigtige destination.' }
    end

    local typeCfg = Config.Agri.TaskTypes[row.type]
    if typeCfg and typeCfg.vehicleGroup then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 then
            return { success = false, msg = 'Du skal sidde i det rigtige køretøj.' }
        end
        local model = GetEntityModel(veh)
        if not VehicleAllowedForGroup(model, typeCfg.vehicleGroup) then
            return { success = false, msg = 'Forkert køretøj til denne opgave.' }
        end
    end

    data.stops[expectedIndex].done = true

    local allDone = true
    for _, s in ipairs(data.stops) do
        if not s.done then allDone = false; break end
    end

    if allDone then
        local xp = AH.GetXPlayer(src)
        if not xp then return { success = false, msg = 'Spillerdata ikke fundet.' } end

        MySQL.update.await('UPDATE agrihub_tasks SET status = "completed", completed_at = NOW(), data = ? WHERE task_id = ? AND status = "active"', { json.encode(data), taskId })
        AH.Pay(xp, 'bank', row.reward)
        ReleaseTaskVehicles(src, taskId)
        AH.LogAction('deliveries', 'TASK_COMPLETED', src, { taskId = taskId, type = row.type, reward = row.reward })

        return { success = true, completed = true, reward = row.reward }
    end

    MySQL.update.await('UPDATE agrihub_tasks SET data = ? WHERE task_id = ?', { json.encode(data), taskId })
    return { success = true, completed = false, nextIndex = expectedIndex + 1 }
end)

-- ─── KØRETØJ TIL OPGAVEN (MM-vehiclekeys-integration, samme mønster
--     som server/rental.lua's npc:create -> vehicleSpawned) ────────
lib.callback.register('masitz_agrihub:tasks:requestVehicle', function(src, taskId)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Ikke logget ind.' } end

    taskId = tostring(taskId or '')
    local row = MySQL.single.await('SELECT player_identifier, status FROM agrihub_tasks WHERE task_id = ?', { taskId })
    if not row or row.status ~= 'active' or row.player_identifier ~= session.identifier then
        return { success = false, msg = 'Ugyldig opgave.' }
    end

    local plate = AH.GenerateJobPlate()
    if not plate then return { success = false, msg = 'Ingen ledige plader lige nu — prøv igen om lidt.' } end

    AH.RegisterVehicle(plate, { src = src, type = 'task', refId = taskId })
    return { success = true, plate = plate }
end)

RegisterNetEvent('masitz_agrihub:tasks:vehicleSpawned', function(plate)
    local src = source
    plate = AH.NormPlate(plate)
    local record = plate and AH.GetVehicleRecord(plate)
    if not record or record.src ~= src or record.type ~= 'task' then return end
    AH.GiveKey(src, plate)
end)

local function ReleaseTaskVehicles(src, taskId)
    for plate, record in pairs(AH.ActiveVehicles) do
        if record.type == 'task' and record.refId == taskId and record.src == src then
            AH.RemoveKey(src, plate)
            AH.UnregisterVehicle(plate)
        end
    end
end

-- ─── ANNULLÉR (spiller opgiver en opgave, den frigives til andre) ──
lib.callback.register('masitz_agrihub:tasks:cancel', function(src, taskId)
    local session = AH.RequireSession(src)
    if not session then return { success = false } end
    taskId = tostring(taskId or '')

    local changed = MySQL.update.await(
        'UPDATE agrihub_tasks SET status = "available", player_identifier = NULL, claimed_at = NULL WHERE task_id = ? AND status = "active" AND player_identifier = ?',
        { taskId, session.identifier }
    )
    if changed and changed > 0 then
        ReleaseTaskVehicles(src, taskId)
        AH.LogAction('deliveries', 'TASK_CANCELLED', src, { taskId = taskId })
        return { success = true }
    end
    return { success = false }
end)

-- ─── DISCONNECT (§50, §78) — frigiv ufærdige opgaver til andre ────
AH.RegisterCleanupHook(function(src)
    local session = AH.Sessions[src]
    if not session then return end
    MySQL.update(
        'UPDATE agrihub_tasks SET status = "available", player_identifier = NULL, claimed_at = NULL WHERE status = "active" AND player_identifier = ?',
        { session.identifier }
    )
end)

AH.Log('server/tasks.lua indlæst.')
