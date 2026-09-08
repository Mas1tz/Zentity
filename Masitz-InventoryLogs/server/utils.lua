-- ============================================================
--  Masitz-InventoryLogs | server/utils.lua
--  Small, dependency-free helpers shared by the rest of the
--  resource. Nothing here touches the network or the database.
-- ============================================================

Utils = {}

local INVENTORY_TYPE_LABELS = {
    player        = 'Player Inventory',
    stash         = 'Stash',
    trunk         = 'Vehicle Trunk',
    glovebox      = 'Glovebox',
    drop          = 'Ground Drop',
    container     = 'Container',
    dumpster      = 'Dumpster',
    policeevidence = 'Police Evidence',
    temp          = 'Temporary Stash',
    shop          = 'Shop',
    newdrop       = 'Ground Drop',
    otherplayer   = 'Player Inventory',
}

--- Human readable label for an ox_inventory inventory `type` string.
--- Falls back to 'Unknown' rather than guessing when we don't recognise it -
--- this can legitimately happen if a third-party resource registers a custom
--- inventory type we've never seen.
---@param invType string?
---@return string
function Utils.InventoryTypeLabel(invType)
    if not invType then return 'Unknown' end
    return INVENTORY_TYPE_LABELS[invType] or ('Unknown (%s)'):format(invType)
end

--- ox_inventory ids trunk/glovebox inventories as `"trunk"..plate` or
--- `"glove"..plate` (both 5-character prefixes) - verified directly against
--- ox_inventory's own `loadInventoryData`. We derive the plate from the id
--- instead of guessing or inventing a lookup.
---@param invId string?
---@param invType string?
---@return string?
function Utils.ExtractPlate(invId, invType)
    if type(invId) ~= 'string' then return nil end
    if invType == 'trunk' or invType == 'glovebox' then
        local plate = invId:sub(6)
        if plate ~= '' then return plate end
    end
    return nil
end

--- ox_inventory's swapItems hook payload has an inconsistent `toSlot` field:
--- it's the full slot table when the destination slot already holds an item,
--- or a bare slot number when the destination is empty. This normalizes both
--- shapes into `{ slot = number, name = string?, count = number?, metadata = table? }`.
---@param field table|number|nil
---@return table
function Utils.NormalizeSlotField(field)
    if type(field) == 'table' then
        return field
    elseif type(field) == 'number' then
        return { slot = field }
    end
    return {}
end

--- JSON-encodes item metadata for safe inclusion in a log entry, truncating
--- oversized payloads so a single item can never blow up a Discord embed or
--- a database column. Returns nil when metadata is disabled, empty, or fails
--- to encode.
---@param metadata table?
---@return string?
function Utils.SanitizeMetadata(metadata)
    if not Config.Metadata.enabled then return nil end
    if type(metadata) ~= 'table' or not next(metadata) then return nil end

    local ok, encoded = pcall(json.encode, metadata)
    if not ok or type(encoded) ~= 'string' then return nil end

    local maxLen = Config.Metadata.maxLength or 400
    if #encoded > maxLen then
        encoded = encoded:sub(1, maxLen) .. '...'
    end

    return encoded
end

--- Truncates an arbitrary string to `len` characters, appending "..." when
--- truncation actually happened.
---@param str string?
---@param len number
---@return string?
function Utils.Truncate(str, len)
    if type(str) ~= 'string' then return str end
    if #str <= len then return str end
    return str:sub(1, len) .. '...'
end

--- Formats a unix timestamp as DD/MM/YYYY HH:MM:SS for embeds/console output.
---@param unixTime number?
---@return string
function Utils.FormatTimestamp(unixTime)
    return os.date('%d/%m/%Y %H:%M:%S', unixTime or os.time())
end

--- Formats a vector3-like table/vector as "x, y, z" rounded to 1 decimal.
---@param coords vector3|table|nil
---@return string?
function Utils.FormatCoords(coords)
    if not coords or not coords.x then return nil end
    return ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z)
end

--- Safe wrapper around GetEntityCoords(GetPlayerPed(source)) - never throws,
--- returns nil if the player/ped isn't resolvable (e.g. mid-disconnect).
---@param source number?
---@return vector3?
function Utils.GetPlayerCoords(source)
    if not source or type(source) ~= 'number' then return nil end

    local ok, ped = pcall(GetPlayerPed, source)
    if not ok or not ped or ped == 0 then return nil end

    local okCoords, coords = pcall(GetEntityCoords, ped)
    if not okCoords then return nil end

    return coords
end

--- Builds a short, deterministic dedup fingerprint out of the key fields of
--- a normalized log entry. Used purely as an in-memory cache key, not a
--- cryptographic hash.
---@param entry table
---@return string
function Utils.BuildFingerprint(entry)
    return table.concat({
        tostring(entry.action),
        tostring(entry.player and entry.player.source),
        tostring(entry.item and entry.item.name),
        tostring(entry.item and entry.item.amount),
        tostring(entry.from and entry.from.id),
        tostring(entry.from and entry.from.slot),
        tostring(entry.to and entry.to.id),
        tostring(entry.to and entry.to.slot),
    }, '|')
end

function Utils.DebugPrint(...)
    if not Config.Debug then return end
    local args = { ... }
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    print(('^3[Masitz-InventoryLogs]^7 %s'):format(table.concat(args, ' ')))
end

function Utils.Warn(msg)
    print(('^1[Masitz-InventoryLogs]^7 %s'):format(msg))
end
