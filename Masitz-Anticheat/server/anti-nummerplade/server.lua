--[[
    ============================================================================
    Masitz-Anticheat — anti-nummerplade — server.lua
    ============================================================================

    SERVER = AUTHORITY. Intet i dette script stoler på en værdi, der kommer
    direkte fra en client, uden selv at blive verificeret mod databasen eller
    mod en native, som serveren selv læser.

    Kernedesign (se punkt 41/42 i specifikationen, og "SECURITY DESIGN" i
    leverance-dokumentet for den fulde begrundelse):

      - Enhver KØRETØJS-PLADE serveren "kender" (TrackedVehicles[netId].plate)
        er den eneste sandhed. Den ændres KUN af server-koden selv, aldrig som
        reaktion på en clients påstand.
      - Den eneste vej til en legitim pladeændring er den atomiske funktion
        AuthorizePlateChange() nedenfor (eksporteret til andre resources).
        Den udfører ownership-check, item-check, duplicate-check, DB-write og
        selve native-kaldet i ÉT uafbrudt kald — der findes derfor ikke noget
        separat "authorization event", en client kan replaye eller spoofe.
      - Hvis et køretøjs faktiske plade (læst via native, server-side) på noget
        tidspunkt afviger fra den plade serveren selv sidst satte, bliver det
        altid opfattet som en uautoriseret ændring, revertet med det samme, og
        klassificeret/logget/eventuelt banned ud fra hvor alvorlig den er.

    OneSync-krav: Dette modul læser native vehicle-state (plate, entity-owner)
    server-side. Det kræver at OneSync er aktiveret (Infinity/Legacy). Uden
    OneSync har serveren ingen synlig entity-state at verificere imod, og
    modulet kan ikke fungere korrekt — se "Known limitations" i leverancen.
]]

if not Config or not Config.AntiNummerplade then
    print("^1[Masitz-Anticheat] [Anti-Nummerplade] [ERROR]^0 Config.AntiNummerplade mangler - modulet starter ikke.")
    return
end

local C = Config.AntiNummerplade

if not C.Enabled then
    print("^3[Masitz-Anticheat] [Anti-Nummerplade] [INFO]^0 Modulet er deaktiveret i config (Enabled = false).")
    return
end

local ESX = exports[C.ESXResourceName]:getSharedObject()

-- ============================================================================
-- DETECTION LEVELS
-- ============================================================================

local LEVEL = {
    NORMAL              = 0, -- ingen afvigelse
    INVALID_REQUEST      = 1, -- malformed/ugyldigt request (fx tomt plate-navn)
    SUSPICIOUS           = 2, -- afvigelse uden klar ejerskabs-kollision (lav confidence)
    STRONG_EVIDENCE      = 3, -- bypass af den legitime flow på spillerens EGET køretøj
    CONFIRMED            = 4, -- vehicle/plate ejerskab matcher IKKE den ansvarlige spiller
    CRITICAL             = 5, -- forsøg på at overtage en ANDEN spillers registrerede plade
}

-- ============================================================================
-- IN-MEMORY STATE
--
-- Alt herunder er runtime-cache. Databasen (owned_vehicles + Masitz-Anticheat's
-- egne tabeller) er altid source of truth og kan altid genopbygge denne state
-- efter et resource/server restart (se sektion "RESTART BEHAVIOUR" nedenfor).
-- ============================================================================

---@type table<number, table> netId -> { entity, plate, owner, lastDriverSource, watchUntil, lastCheck }
local TrackedVehicles = {}

---@type table<string, boolean> plate -> true while an AuthorizePlateChange for that plate is in-flight
local PendingChange = {}

---@type table<number, number> source -> last hint timestamp (ms, GetGameTimer)
local ClientHintLastSeen = {}

---@type table<string, table> identifier -> { {level, time}, ... } recent offences for repeat-offence escalation
local OffenceLog = {}

-- ============================================================================
-- UTILITIES
-- ============================================================================

local function DebugPrint(fmt, ...)
    if C.Debug then
        print(("^5[Masitz-Anticheat] [Anti-Nummerplade] [DEBUG]^0 " .. fmt):format(...))
    end
end

local function InfoPrint(fmt, ...)
    print(("^2[Masitz-Anticheat] [Anti-Nummerplade] [INFO]^0 " .. fmt):format(...))
end

local function WarnPrint(fmt, ...)
    print(("^3[Masitz-Anticheat] [Anti-Nummerplade] [WARNING]^0 " .. fmt):format(...))
end

local function DetectionPrint(fmt, ...)
    print(("^1[Masitz-Anticheat] [Anti-Nummerplade] [DETECTION]^0 " .. fmt):format(...))
end

local function BanPrint(fmt, ...)
    print(("^8[Masitz-Anticheat] [Anti-Nummerplade] [BAN]^0 " .. fmt):format(...))
end

local function ErrorPrint(fmt, ...)
    print(("^1[Masitz-Anticheat] [Anti-Nummerplade] [ERROR]^0 " .. fmt):format(...))
end

-- Central normalization: everything that touches a plate value goes through
-- this. Upper-case, trimmed, internal whitespace collapsed to a single space.
local function NormalizePlate(plate)
    if type(plate) ~= "string" then return nil end
    plate = plate:upper()
    plate = plate:gsub("^%s+", ""):gsub("%s+$", "")
    plate = plate:gsub("%s+", " ")
    if plate == "" then return nil end
    return plate
end

local function ValidatePlateFormat(plate)
    if not plate then return false, "empty" end
    local len = #plate
    if len < C.MinPlateLength or len > C.MaxPlateLength then
        return false, "length"
    end
    if not plate:match(C.PlateCharsetPattern) then
        return false, "charset"
    end
    return true, nil
end

-- Builds a structured identifier table for a connected player. Tolerant of
-- any identifier being absent (never assumes steam/discord/xbl/etc. exist).
local function GetIdentifiersTable(source)
    local ids = {}
    local list = GetPlayerIdentifiers(source)
    if list then
        for _, id in ipairs(list) do
            local prefix, _ = id:match("^(%w+):(.+)$")
            if prefix then
                ids[prefix] = id
            end
        end
    end

    local ok, endpoint = pcall(GetPlayerEndpoint, source)
    if ok and endpoint and type(endpoint) == "string" then
        ids.ip = endpoint:match("^([^:]+)") or endpoint
    end

    return ids
end

local function SafeGetPlayerName(source)
    local ok, name = pcall(GetPlayerName, source)
    if ok and name then return name end
    return "unknown"
end

-- ============================================================================
-- DATABASE HELPERS (parameterized only - never string-concatenated SQL)
-- ============================================================================

local function DbGetVehicleByPlate(plate)
    local ok, row = pcall(function()
        return MySQL.single.await("SELECT `owner`, `plate` FROM `owned_vehicles` WHERE `plate` = ?", { plate })
    end)
    if not ok then
        ErrorPrint("DB fejl i DbGetVehicleByPlate(%s): %s", tostring(plate), tostring(row))
        return nil, true -- (nil result, dbError = true)
    end
    return row, false
end

-- Atomically re-points the primary key `plate` for the row currently owned by
-- `owner`. Relies on owned_vehicles.plate being a PRIMARY KEY: if newPlate
-- already exists as another row's key, MySQL rejects this with a duplicate-key
-- error, which we treat as an authoritative "denied" - this is a second,
-- DB-level line of defense against races/duplicates on top of the in-memory
-- PendingChange mutex (see AuthorizePlateChange).
local function DbUpdateVehiclePlate(oldPlate, newPlate, owner)
    local ok, result = pcall(function()
        return MySQL.update.await(
            "UPDATE `owned_vehicles` SET `plate` = ? WHERE `plate` = ? AND `owner` = ?",
            { newPlate, oldPlate, owner }
        )
    end)
    if not ok then
        -- Most likely a duplicate-key error (race condition) or connection issue.
        return false, result
    end
    return (result == 1), nil
end

-- NOTE ON NAMED PARAMETERS: most of these fields are routinely nil (not every
-- event has a responsible player, plate collision, etc.). A POSITIONAL `?`
-- params array with a `nil` hole in the middle is unsafe here - Lua's
-- `ipairs`/`#` semantics over a table with holes are implementation-defined,
-- and depending on how the underlying driver iterates the array, a nil in
-- the middle can silently truncate or misalign the remaining parameters.
-- Named `:key` parameters (a plain hash table) sidestep that entirely, since
-- a missing/nil key is simply absent rather than a hole in a sequence.
local function DbInsertSecurityEvent(level, code, data)
    local ok, err = pcall(function()
        MySQL.insert.await(
            [[INSERT INTO `masitz_anticheat_security_events`
                (`level`, `detection_type`, `plate_old`, `plate_new`, `vehicle_owner`,
                 `responsible_identifier`, `responsible_name`, `source_id`, `duplicate_owner`,
                 `action_taken`, `details`)
              VALUES (:level, :code, :plateOld, :plateNew, :vehicleOwner,
                      :responsibleIdentifier, :responsibleName, :sourceId, :duplicateOwner,
                      :actionTaken, :details)]],
            {
                level = level,
                code = code,
                plateOld = data.plateOld,
                plateNew = data.plateNew,
                vehicleOwner = data.vehicleOwner,
                responsibleIdentifier = data.responsibleIdentifier,
                responsibleName = data.responsibleName,
                sourceId = data.sourceId,
                duplicateOwner = data.duplicateOwner,
                actionTaken = data.actionTaken,
                details = json.encode(data.details or {}),
            }
        )
    end)
    if not ok then
        ErrorPrint("Kunne ikke skrive security event til databasen: %s", tostring(err))
    end
end

local function DbInsertBan(data)
    local ids = data.ids or {}
    local ok, result = pcall(function()
        return MySQL.insert.await(
            [[INSERT INTO `masitz_anticheat_bans`
                (`player_name`, `identifier_license`, `identifier_license2`, `identifier_discord`,
                 `identifier_steam`, `identifier_fivem`, `identifier_xbl`, `identifier_live`,
                 `identifier_ip`, `module`, `detection_type`, `confidence_level`, `reason`, `evidence`)
              VALUES (:playerName, :license, :license2, :discord,
                      :steam, :fivem, :xbl, :live,
                      :ip, :module, :detectionType, :level, :reason, :evidence)]],
            {
                playerName = data.playerName,
                license = ids.license,
                license2 = ids.license2,
                discord = ids.discord,
                steam = ids.steam,
                fivem = ids.fivem,
                xbl = ids.xbl,
                live = ids.live,
                ip = ids.ip,
                module = "anti-nummerplade",
                detectionType = data.detectionType,
                level = data.level,
                reason = data.reason,
                evidence = json.encode(data.evidence or {}),
            }
        )
    end)
    if not ok then
        ErrorPrint("Kunne ikke skrive ban til databasen: %s", tostring(result))
        return nil
    end
    return result
end

-- ============================================================================
-- ox_inventory INTEGRATION (fail-closed: any error is treated as "no item")
-- ============================================================================

local function GetPlateItemCount(source)
    local ok, count = pcall(function()
        return exports.ox_inventory:GetItemCount(source, C.PlateItem)
    end)
    if ok and type(count) == "number" then return count end

    ok, count = pcall(function()
        return exports.ox_inventory:Search(source, "count", C.PlateItem)
    end)
    if ok and type(count) == "number" then return count end

    WarnPrint("Kunne ikke læse ox_inventory item-count for '%s' (source %s) - antager 0 (fail-safe deny).", C.PlateItem, tostring(source))
    return 0
end

local function RemovePlateItem(source)
    local ok, success = pcall(function()
        return exports.ox_inventory:RemoveItem(source, C.PlateItem, 1)
    end)
    return ok and success == true
end

-- ============================================================================
-- DISCORD LOGGING
-- ============================================================================

local function ResolveWebhook(kind)
    local specific = ({
        legit = C.WebhookLegit,
        suspicious = C.WebhookSuspicious,
        violation = C.WebhookViolation,
        ban = C.WebhookBan,
    })[kind]
    if specific and specific ~= "" then return specific end
    return C.Webhook
end

local function SendDiscordEmbed(kind, title, color, fields)
    if not C.DiscordLogging then return end
    local webhook = ResolveWebhook(kind)
    if not webhook or webhook == "" then return end

    local embedFields = {}
    for _, f in ipairs(fields) do
        embedFields[#embedFields + 1] = { name = f[1], value = tostring(f[2] ~= nil and f[2] ~= "" and f[2] or "n/a"), inline = f[3] ~= false }
    end

    local payload = {
        username = C.DiscordUsername,
        avatar_url = (C.DiscordAvatar ~= "" and C.DiscordAvatar or nil),
        embeds = {
            {
                title = title,
                color = color,
                fields = embedFields,
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                footer = { text = "Masitz-Anticheat / anti-nummerplade" },
            },
        },
    }

    PerformHttpRequest(webhook, function() end, "POST", json.encode(payload), { ["Content-Type"] = "application/json" })
end

local function LogLegitChange(source, xPlayer, oldPlate, newPlate, vehicleOwner)
    SendDiscordEmbed("legit", "🟢 Legitimate Plate Change", 0x2ecc71, {
        { "Player", ("%s (%s)"):format(SafeGetPlayerName(source), source), true },
        { "Server ID", source, true },
        { "Old plate", oldPlate, true },
        { "New plate", newPlate, true },
        { "Owner", vehicleOwner, true },
        { "Item verified", "yes", true },
        { "Timestamp", os.date("%Y-%m-%d %H:%M:%S"), false },
    })
end

local function LogSuspicious(reasonText, data)
    SendDiscordEmbed("suspicious", "🟡 Suspicious Plate Manipulation", 0xf1c40f, {
        { "Player", data.playerName, true },
        { "Server ID", data.sourceId, true },
        { "Reason", reasonText, false },
        { "Old plate", data.plateOld, true },
        { "Attempted plate", data.plateNew, true },
        { "Timestamp", os.date("%Y-%m-%d %H:%M:%S"), false },
    })
end

local function LogViolation(reasonText, data)
    SendDiscordEmbed("violation", "🔴 CONFIRMED ANTI-CHEAT VIOLATION", 0xe74c3c, {
        { "Player", data.playerName, true },
        { "Server ID", data.sourceId, true },
        { "Reason", reasonText, false },
        { "Old plate", data.plateOld, true },
        { "Attempted plate", data.plateNew, true },
        { "Actual owner of attempted plate", data.duplicateOwner, false },
        { "Vehicle owner", data.vehicleOwner, true },
        { "Detection level", data.level, true },
        { "Timestamp", os.date("%Y-%m-%d %H:%M:%S"), false },
    })
end

local function LogBan(playerName, sourceId, reasonText, data, ids, banId)
    SendDiscordEmbed("ban", "🚨 MASITZ ANTICHEAT BAN", 0x992d22, {
        { "Ban ID", banId, true },
        { "Player", playerName, true },
        { "Server ID", sourceId, true },
        { "Reason", reasonText, false },
        { "Old plate", data.plateOld, true },
        { "Attempted plate", data.plateNew, true },
        { "Vehicle owner", data.vehicleOwner, true },
        { "Attempted by", data.responsibleIdentifier, true },
        { "License", ids.license, true },
        { "License2", ids.license2, true },
        { "Discord", ids.discord, true },
        { "Steam", ids.steam, true },
        { "IP", ids.ip, true },
        { "Detection confidence", data.level, true },
        { "Timestamp", os.date("%Y-%m-%d %H:%M:%S"), false },
    })
end

-- ============================================================================
-- BAN LOGIC
-- ============================================================================

-- section 15/17: a single weak signal (IP alone, discord alone, ...) is never
-- sufficient for a permanent ban. Only a strong identifier (license/license2)
-- OR at least two correlated weak identifiers matching the SAME ban record can
-- block a connection.
local function EvaluateBanStatusForConnect(ids)
    local strongFields = { { "license", "identifier_license" }, { "license2", "identifier_license2" } }
    local strongClauses, strongParams = {}, {}
    for _, f in ipairs(strongFields) do
        if ids[f[1]] then
            strongClauses[#strongClauses + 1] = ("`%s` = ?"):format(f[2])
            strongParams[#strongParams + 1] = ids[f[1]]
        end
    end

    if #strongClauses > 0 then
        local ok, row = pcall(function()
            return MySQL.single.await(
                ("SELECT `id`, `reason` FROM `masitz_anticheat_bans` WHERE `active` = 1 AND (%s) LIMIT 1"):format(table.concat(strongClauses, " OR ")),
                strongParams
            )
        end)
        if ok and row then
            return { blocked = true, banId = row.id, reason = row.reason }
        end
    end

    local weakFields = { { "discord", "identifier_discord" }, { "steam", "identifier_steam" }, { "ip", "identifier_ip" } }
    local matchCounts = {}
    local matchReasons = {}
    for _, f in ipairs(weakFields) do
        if ids[f[1]] then
            local ok, rows = pcall(function()
                return MySQL.query.await(
                    ("SELECT `id`, `reason` FROM `masitz_anticheat_bans` WHERE `active` = 1 AND `%s` = ?"):format(f[2]),
                    { ids[f[1]] }
                )
            end)
            if ok and rows then
                for _, r in ipairs(rows) do
                    matchCounts[r.id] = (matchCounts[r.id] or 0) + 1
                    matchReasons[r.id] = r.reason
                end
            end
        end
    end

    for banId, count in pairs(matchCounts) do
        if count >= 2 then
            return { blocked = true, banId = banId, reason = matchReasons[banId] }
        elseif count == 1 then
            -- low-confidence, single weak signal: never block, just flag for admins.
            return { blocked = false, lowConfidenceBanId = banId }
        end
    end

    return { blocked = false }
end

local function RegisterOffence(identifier, level)
    if not identifier then return end
    local now = GetGameTimer()
    local log = OffenceLog[identifier] or {}
    -- prune old entries outside the window
    local pruned = {}
    for _, entry in ipairs(log) do
        if (now - entry.time) <= C.RepeatOffenceWindowMs then
            pruned[#pruned + 1] = entry
        end
    end
    pruned[#pruned + 1] = { level = level, time = now }
    OffenceLog[identifier] = pruned
    return #pruned
end

local function BanPlayer(source, level, detectionType, reasonText, data)
    if not C.SaveBans then return end

    local ids = source and GetIdentifiersTable(source) or {}
    local playerName = source and SafeGetPlayerName(source) or "unknown (offline)"

    local banId = DbInsertBan({
        playerName = playerName,
        ids = ids,
        detectionType = detectionType,
        level = level,
        reason = reasonText,
        evidence = data,
    })

    BanPrint("Player %s (source %s) banned. Reason: %s", playerName, tostring(source), reasonText)
    LogBan(playerName, source or "?", reasonText, data, ids, banId or "?")

    if source and C.KickOnBan then
        pcall(DropPlayer, source, ("Masitz-Anticheat\nDu er permanent banned.\nÅrsag: %s\nBan ID: %s"):format(reasonText, banId or "?"))
    end
end

-- ============================================================================
-- VEHICLE TRACKING
-- ============================================================================

local function TrackVehicle(netId, entity, plate, owner, persistent)
    TrackedVehicles[netId] = {
        entity = entity,
        plate = plate,
        owner = owner, -- nil for unregistered vehicles
        lastDriverSource = nil,
        watchUntil = persistent and nil or (os.time() + C.UnregisteredWatchWindowSec),
        lastCheck = os.time(),
    }
end

-- Called after a short delay following entityCreated, to let a legitimate
-- spawn script (the garage resource) finish setting the vehicle's plate
-- before we adopt it as our baseline.
local function TryBindFromSpawn(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    if GetEntityType(entity) ~= 2 then return end

    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId == 0 then return end
    if TrackedVehicles[netId] then return end -- already bound (e.g. via driver-enter)

    local ok, rawPlate = pcall(GetVehicleNumberPlateText, entity)
    if not ok or not rawPlate then return end
    local plate = NormalizePlate(rawPlate)
    if not plate then return end

    local row = DbGetVehicleByPlate(plate)
    if row then
        TrackVehicle(netId, entity, plate, row.owner, true)
        DebugPrint("Bound owned vehicle at spawn: netId=%s plate=%s owner=%s", netId, plate, row.owner)
    end
    -- If not found: this is not a registered vehicle. We deliberately do NOT
    -- track it yet - it will be picked up on-demand the moment a player
    -- actually enters it as a driver (see BindFromDriverEnter), which keeps
    -- the tracked set bounded to player-relevant vehicles instead of every
    -- ambient/NPC car spawned on the map.
end

-- CEventNetworkPlayerEnteredVehicle fires for ANY seat, not just the driver's -
-- a passenger entering triggers it too. Only treat `enteringSource` as the
-- vehicle's "responsible" party (used for later violation attribution) once
-- we've confirmed server-side that they are actually the one in the driver
-- seat; otherwise we still use the event to bind/watch the vehicle (useful
-- for the unregistered-vehicle Attack-2 coverage), just without attributing
-- responsibility to what may be an innocent passenger.
local function BindFromDriverEnter(entity, enteringSource)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    if GetEntityType(entity) ~= 2 then return end

    local netId = NetworkGetNetworkIdFromEntity(entity)
    if not netId or netId == 0 then return end

    local isDriver = false
    if enteringSource then
        local ok, driverPed = pcall(GetPedInVehicleSeat, entity, -1)
        if ok and driverPed and driverPed ~= 0 then
            local ok2, driverPedOwner = pcall(NetworkGetEntityOwner, driverPed)
            isDriver = ok2 and driverPedOwner == enteringSource
        end
    end

    local tracked = TrackedVehicles[netId]
    if tracked then
        if isDriver then
            tracked.lastDriverSource = enteringSource
        end
        if tracked.owner == nil and C.EnableUnregisteredVehicleWatch then
            tracked.watchUntil = os.time() + C.UnregisteredWatchWindowSec
        end
        return
    end

    if not C.EnableUnregisteredVehicleWatch then return end

    local ok, rawPlate = pcall(GetVehicleNumberPlateText, entity)
    if not ok or not rawPlate then return end
    local plate = NormalizePlate(rawPlate)
    if not plate then return end

    local row = DbGetVehicleByPlate(plate)
    TrackVehicle(netId, entity, plate, row and row.owner or nil, row ~= nil)
    if isDriver then
        TrackedVehicles[netId].lastDriverSource = enteringSource
    end
    DebugPrint("Bound vehicle on vehicle-enter: netId=%s plate=%s owner=%s isDriver=%s", netId, plate, row and row.owner or "nil", tostring(isDriver))
end

local function ClassifyViolation(tracked, newPlate, duplicateOwner, responsibleIdentifier)
    if duplicateOwner and duplicateOwner ~= tracked.owner then
        return LEVEL.CRITICAL, "plate_theft", ("Attempted to change plate to '%s', which is already registered to another player."):format(newPlate)
    end

    if tracked.owner and responsibleIdentifier and responsibleIdentifier ~= tracked.owner then
        return LEVEL.CONFIRMED, "unauthorized_vehicle_manipulation", "Vehicle plate was altered by someone other than its registered owner, with no authorized operation on record."
    end

    if tracked.owner == nil then
        return LEVEL.SUSPICIOUS, "unregistered_vehicle_plate_change", "Plate of an unregistered vehicle changed outside the legitimate plate-change flow."
    end

    return LEVEL.STRONG_EVIDENCE, "bypassed_authorization_flow", "Vehicle's own plate changed without going through the authorized server-side flow."
end

local function HandlePlateDrift(netId, tracked, newPlate)
    local entity = tracked.entity
    if not entity or not DoesEntityExist(entity) then
        TrackedVehicles[netId] = nil
        return
    end

    local responsibleSource = nil
    local ok, owner = pcall(NetworkGetEntityOwner, entity)
    if ok and owner and owner > 0 then
        responsibleSource = owner
    elseif tracked.lastDriverSource then
        responsibleSource = tracked.lastDriverSource
    end

    local responsibleIdentifier, responsibleName = nil, nil
    if responsibleSource then
        local xPlayer = ESX.GetPlayerFromId(responsibleSource)
        if xPlayer then
            responsibleIdentifier = xPlayer.identifier
        end
        responsibleName = SafeGetPlayerName(responsibleSource)
    end

    -- Always revert immediately: this is the "block", not just "detect".
    local revertOk = pcall(SetVehicleNumberPlateText, entity, tracked.plate)
    if not revertOk then
        ErrorPrint("Kunne ikke revertere plade for netId=%s til '%s'", netId, tracked.plate)
    end

    local oldPlate = tracked.plate
    local dupRow = DbGetVehicleByPlate(newPlate)
    local duplicateOwner = dupRow and dupRow.owner or nil

    local level, code, reasonText = ClassifyViolation(tracked, newPlate, duplicateOwner, responsibleIdentifier)

    local eventData = {
        plateOld = oldPlate,
        plateNew = newPlate,
        vehicleOwner = tracked.owner,
        responsibleIdentifier = responsibleIdentifier,
        responsibleName = responsibleName,
        sourceId = responsibleSource,
        duplicateOwner = duplicateOwner,
        actionTaken = "reverted",
        details = { netId = netId },
    }

    DetectionPrint("[%s] level=%s plate %s -> %s (vehicle owner=%s, responsible=%s)",
        code, level, oldPlate, newPlate, tostring(tracked.owner), tostring(responsibleIdentifier))

    if level >= LEVEL.CONFIRMED then
        DbInsertSecurityEvent(level, code, eventData)
        LogViolation(reasonText, {
            playerName = responsibleName or "unknown",
            sourceId = responsibleSource or "?",
            plateOld = oldPlate,
            plateNew = newPlate,
            duplicateOwner = duplicateOwner,
            vehicleOwner = tracked.owner,
            level = level,
        })
    elseif level >= LEVEL.SUSPICIOUS then
        DbInsertSecurityEvent(level, code, eventData)
        LogSuspicious(reasonText, {
            playerName = responsibleName or "unknown",
            sourceId = responsibleSource or "?",
            plateOld = oldPlate,
            plateNew = newPlate,
        })
    end

    if responsibleIdentifier then
        local count = RegisterOffence(responsibleIdentifier, level)
        if level >= C.BanConfidenceLevel and C.BanEnabled then
            eventData.actionTaken = "banned"
            BanPlayer(responsibleSource, level, code, reasonText, eventData)
        elseif C.EscalateRepeatOffences and count and count >= C.RepeatOffenceThreshold and C.BanEnabled then
            eventData.actionTaken = "banned_repeat_offence"
            BanPlayer(responsibleSource, level, "repeat_offences_" .. code,
                ("Repeated suspicious plate-manipulation activity (%d events within window): %s"):format(count, reasonText),
                eventData)
        end
    end
end

local function VerifyVehicleIntegrity(netId)
    local tracked = TrackedVehicles[netId]
    if not tracked then return end

    local entity = tracked.entity
    if not entity or not DoesEntityExist(entity) then
        TrackedVehicles[netId] = nil
        return
    end
    if GetEntityType(entity) ~= 2 then
        TrackedVehicles[netId] = nil
        return
    end

    local ok, rawPlate = pcall(GetVehicleNumberPlateText, entity)
    if not ok or not rawPlate then return end
    local currentPlate = NormalizePlate(rawPlate)
    if not currentPlate then return end

    tracked.lastCheck = os.time()

    if currentPlate == tracked.plate then
        return
    end

    HandlePlateDrift(netId, tracked, currentPlate)
end

-- ============================================================================
-- EVENTS
-- ============================================================================

AddEventHandler("entityCreated", function(entity)
    if not entity or entity == 0 then return end
    local ok, entityType = pcall(GetEntityType, entity)
    if not ok or entityType ~= 2 then return end

    SetTimeout(C.SpawnBindDelayMs, function()
        TryBindFromSpawn(entity)
    end)
end)

AddEventHandler("entityRemoved", function(entity)
    if not entity or entity == 0 then return end
    local ok, netId = pcall(NetworkGetNetworkIdFromEntity, entity)
    if ok and netId and netId ~= 0 then
        TrackedVehicles[netId] = nil
    end
end)

AddEventHandler("gameEventTriggered", function(eventName, args)
    if eventName ~= "CEventNetworkPlayerEnteredVehicle" then return end
    if not args or not args[1] or not args[2] then return end

    local enteringPed, vehicle = args[1], args[2]
    if not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return end

    local ok, enteringSource = pcall(NetworkGetEntityOwner, enteringPed)
    if not ok or not enteringSource or enteringSource <= 0 then
        enteringSource = nil
    end

    BindFromDriverEnter(vehicle, enteringSource)
end)

AddEventHandler("playerDropped", function()
    local src = source
    ClientHintLastSeen[src] = nil
end)

-- Non-authoritative hint from the client: "please re-check this vehicle now".
-- The server NEVER trusts the plate value in this event - it only uses it to
-- decide which vehicle to re-verify immediately (via its own native read)
-- instead of waiting for the next sweep. Rate-limited to prevent event spam.
RegisterNetEvent("masitz_anticheat:anp:hintCheck", function(netId)
    local src = source
    if type(netId) ~= "number" then return end

    local now = GetGameTimer()
    local last = ClientHintLastSeen[src] or 0
    if (now - last) < C.ClientHintRateLimitMs then return end
    ClientHintLastSeen[src] = now

    if TrackedVehicles[netId] then
        VerifyVehicleIntegrity(netId)
    end
end)

-- ============================================================================
-- BAN ENFORCEMENT ON CONNECT
-- ============================================================================

AddEventHandler("playerConnecting", function(_, _, deferrals)
    local src = source
    deferrals.defer()

    Wait(0)

    if not C.BanEnabled or not C.SaveBans then
        deferrals.done()
        return
    end

    deferrals.update("Masitz-Anticheat: verificerer sikkerhedsstatus...")

    local ids = GetIdentifiersTable(src)
    local ok, result = pcall(EvaluateBanStatusForConnect, ids)

    if ok and result and result.blocked then
        deferrals.done(("Du er permanent banned fra denne server.\n\nÅrsag: %s\nBan ID: %s"):format(
            result.reason or "Sikkerhedsovertrædelse", result.banId or "?"))
        return
    end

    if ok and result and result.lowConfidenceBanId then
        WarnPrint("Low-confidence ban-signal match (single weak identifier) for incoming connection (name=%s). Ban ID %s ikke håndhævet automatisk - kræver admin review.",
            SafeGetPlayerName(src), result.lowConfidenceBanId)
    end

    deferrals.done()
end)

-- ============================================================================
-- PERIODIC SWEEP (safety net only - primary detection is event-driven)
--
-- Iterates ONLY the bounded TrackedVehicles set (owned/registered vehicles +
-- vehicles a player is/was recently driving), never every entity on the map.
-- ============================================================================

CreateThread(function()
    while true do
        Wait(C.SweepIntervalMs)

        local now = os.time()
        for netId, tracked in pairs(TrackedVehicles) do
            if tracked.owner == nil and tracked.watchUntil and now > tracked.watchUntil then
                TrackedVehicles[netId] = nil
            else
                -- A single bad entry (unexpected native error, edge-case entity
                -- state) must never kill this thread permanently - that would
                -- silently disable the safety-net sweep for the rest of the
                -- server's uptime with no visible symptom.
                local ok, err = pcall(VerifyVehicleIntegrity, netId)
                if not ok then
                    ErrorPrint("Sweep fejlede for netId=%s: %s", tostring(netId), tostring(err))
                end
            end
        end
    end
end)

-- ============================================================================
-- PUBLIC API (server-to-server only - cannot be called from a client)
-- ============================================================================

-- AuthorizePlateChange(source, vehicleNetId, requestedNewPlate)
--
-- The ONLY legitimate way to change a tracked/registered vehicle's plate.
-- Intended to be called by the (future) reworked nummerplade resource's own
-- SERVER script, after it receives a request from its own client. This
-- function re-derives and re-verifies everything itself from `source` and
-- `vehicleNetId` - it never trusts the calling resource's own judgement about
-- ownership, item possession, or plate validity.
--
-- Returns: boolean success, string reasonCode
local function AuthorizePlateChange(source, vehicleNetId, requestedNewPlate)
    if type(source) ~= "number" or type(vehicleNetId) ~= "number" or type(requestedNewPlate) ~= "string" then
        return false, "invalid_arguments"
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        return false, "invalid_player"
    end

    local entity = NetworkGetEntityFromNetworkId(vehicleNetId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false, "invalid_vehicle"
    end
    if GetEntityType(entity) ~= 2 then
        return false, "not_a_vehicle"
    end

    local ok, rawCurrentPlate = pcall(GetVehicleNumberPlateText, entity)
    if not ok or not rawCurrentPlate then
        return false, "could_not_read_plate"
    end
    local currentPlate = NormalizePlate(rawCurrentPlate)
    if not currentPlate then
        return false, "invalid_current_plate"
    end

    if C.CheckOwnership then
        local row = DbGetVehicleByPlate(currentPlate)
        if not row then
            LogSuspicious("Attempted to authorize a plate change on a vehicle that is not registered in owned_vehicles.", {
                playerName = SafeGetPlayerName(source), sourceId = source, plateOld = currentPlate, plateNew = requestedNewPlate,
            })
            return false, "vehicle_not_registered"
        end
        if row.owner ~= xPlayer.identifier then
            DbInsertSecurityEvent(LEVEL.STRONG_EVIDENCE, "ownership_mismatch_on_authorize", {
                plateOld = currentPlate, plateNew = requestedNewPlate, vehicleOwner = row.owner,
                responsibleIdentifier = xPlayer.identifier, responsibleName = SafeGetPlayerName(source),
                sourceId = source, duplicateOwner = nil, actionTaken = "denied", details = {},
            })
            LogSuspicious("Player attempted to authorize a plate change on a vehicle they do not own.", {
                playerName = SafeGetPlayerName(source), sourceId = source, plateOld = currentPlate, plateNew = requestedNewPlate,
            })
            return false, "not_owner"
        end
    end

    if PendingChange[currentPlate] then
        return false, "operation_in_progress"
    end
    PendingChange[currentPlate] = true

    -- Everything below this point performs DB/inventory awaits, which yield
    -- to other coroutines - the vehicle entity can, in principle, be deleted
    -- from underneath us while we wait (see "vehicle deletion during
    -- validation" in the self-audit). Running it inside pcall guarantees the
    -- PendingChange mutex is always released below, even on an unexpected
    -- native/runtime error, instead of permanently locking this plate.
    local runOk, success, reason = pcall(function()
        if C.CheckItem then
            local count = GetPlateItemCount(source)
            if count < 1 then
                LogSuspicious(("Attempted plate change without holding the required item ('%s')."):format(C.PlateItem), {
                    playerName = SafeGetPlayerName(source), sourceId = source, plateOld = currentPlate, plateNew = requestedNewPlate,
                })
                return false, "missing_item"
            end
        end

        local newPlate = NormalizePlate(requestedNewPlate)
        local validFormat, formatError = ValidatePlateFormat(newPlate)
        if not validFormat then
            return false, "invalid_new_plate_" .. tostring(formatError)
        end

        if newPlate == currentPlate then
            return false, "no_change"
        end

        if C.CheckDuplicatePlates then
            local existing = DbGetVehicleByPlate(newPlate)
            if existing then
                LogSuspicious("Attempted to change plate to one already registered in owned_vehicles.", {
                    playerName = SafeGetPlayerName(source), sourceId = source, plateOld = currentPlate, plateNew = newPlate,
                })
                return false, "plate_already_registered"
            end
        end

        local updated, dbErr = DbUpdateVehiclePlate(currentPlate, newPlate, xPlayer.identifier)
        if not updated then
            WarnPrint("Plate update denied/failed for %s -> %s (owner=%s): %s", currentPlate, newPlate, xPlayer.identifier, tostring(dbErr))
            return false, "database_update_failed"
        end

        if C.ConsumeItemOnAuthorize then
            local removed = RemovePlateItem(source)
            if not removed then
                -- Roll back the plate change if we could not consume the item, so
                -- the DB and inventory state cannot diverge from each other.
                DbUpdateVehiclePlate(newPlate, currentPlate, xPlayer.identifier)
                return false, "item_removal_failed"
            end
        end

        if not DoesEntityExist(entity) then
            -- The vehicle vanished mid-authorization. The DB/inventory side of
            -- the change already committed above (safe/idempotent), but there
            -- is no entity left to write the native plate to. The next
            -- spawn/driver-enter bind for this plate will simply adopt the new
            -- DB value as its baseline, so no inconsistency is left behind.
            return true, "ok_entity_gone"
        end

        -- Update the in-memory baseline BEFORE writing the new plate to the
        -- entity, so the next integrity check sees a consistent state and does
        -- not misclassify this legitimate change as drift.
        local tracked = TrackedVehicles[vehicleNetId]
        if tracked then
            tracked.plate = newPlate
            tracked.owner = xPlayer.identifier
        else
            TrackVehicle(vehicleNetId, entity, newPlate, xPlayer.identifier, true)
        end

        SetVehicleNumberPlateText(entity, newPlate)

        LogLegitChange(source, xPlayer, currentPlate, newPlate, xPlayer.identifier)

        return true, "ok"
    end)

    PendingChange[currentPlate] = nil

    if not runOk then
        ErrorPrint("Uventet fejl under AuthorizePlateChange (%s -> %s): %s", currentPlate, tostring(requestedNewPlate), tostring(success))
        return false, "internal_error"
    end

    return success, reason
end

exports("AuthorizePlateChange", AuthorizePlateChange)

-- Read-only helper for other (future) modules / admin tooling.
exports("GetTrackedVehicle", function(netId)
    local tracked = TrackedVehicles[netId]
    if not tracked then return nil end
    return { plate = tracked.plate, owner = tracked.owner }
end)

-- ============================================================================
-- ADMIN COMMAND
-- ============================================================================

local function IsAdmin(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end
    local group = xPlayer.getGroup()
    for _, allowed in ipairs(C.AdminGroups) do
        if group == allowed then return true end
    end
    return false
end

RegisterCommand("anticheat_status", function(source)
    if source == 0 then
        print(("Masitz-Anticheat: tracking %d vehicles."):format((function()
            local n = 0
            for _ in pairs(TrackedVehicles) do n = n + 1 end
            return n
        end)()))
        return
    end

    if not IsAdmin(source) then return end

    local count = 0
    for _ in pairs(TrackedVehicles) do count = count + 1 end

    TriggerClientEvent("chat:addMessage", source, {
        args = { "Masitz-Anticheat", ("Tracking %d vehicles. BanEnabled=%s Debug=%s"):format(count, tostring(C.BanEnabled), tostring(C.Debug)) },
    })
end, false)

InfoPrint("Modul indlæst. BanEnabled=%s DiscordLogging=%s", tostring(C.BanEnabled), tostring(C.DiscordLogging))
