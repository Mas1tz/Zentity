-- ============================================================
--  Masitz-InventoryLogs | server/logger.lua
--  The single entry point every hook goes through. This is what
--  the spec asks for: one central LogInventoryAction(...) call
--  instead of 20 near-identical logDrop/logGive/logStash functions
--  scattered around. hooks.lua only classifies *what* happened;
--  this file decides *whether* and *where* it gets logged.
-- ============================================================

Logger = {}

local LOGGING_KEY = {
    give                = 'give',
    drop                = 'drop',
    pickup              = 'pickup',
    stash_deposit       = 'stashDeposit',
    stash_withdraw      = 'stashWithdraw',
    trunk_deposit       = 'trunkDeposit',
    trunk_withdraw      = 'trunkWithdraw',
    glovebox_deposit    = 'gloveboxDeposit',
    glovebox_withdraw   = 'gloveboxWithdraw',
    container_store     = 'containerTransfer',
    container_retrieve  = 'containerTransfer',
    evidence_deposit    = 'evidenceTransfer',
    evidence_withdraw   = 'evidenceTransfer',
    dumpster_deposit    = 'dumpsterTransfer',
    dumpster_retrieve   = 'dumpsterTransfer',
    inventory_swap      = 'inventorySwap',
    inventory_stack     = 'inventoryStack',
    inventory_transfer  = 'inventoryTransfer',
    move_slot           = 'moveSlot',
    split_stack         = 'splitStack',
    shop_purchase       = 'shopPurchase',
    open_shop           = 'openShop',
    craft               = 'craft',
    use_item            = 'useItem',
    open_inventory      = 'openInventoryAccess',
}

-- ------------------------------------------------------------
--  Short-lived dedup fingerprint cache. See config.lua for why
--  this exists despite the hook architecture only firing once
--  per real action.
-- ------------------------------------------------------------
local recentActions = {}

local function isDuplicate(fingerprint)
    local now = GetGameTimer()
    local last = recentActions[fingerprint]

    if last and (now - last) < (Config.DedupWindowMs or 1500) then
        return true
    end

    recentActions[fingerprint] = now
    return false
end

CreateThread(function()
    while true do
        Wait(30000)
        local now = GetGameTimer()
        local ttl = (Config.DedupWindowMs or 1500) * 4

        for fingerprint, timestamp in pairs(recentActions) do
            if now - timestamp > ttl then
                recentActions[fingerprint] = nil
            end
        end
    end
end)

---Central logging entry point. Every hook in server/hooks.lua builds a
---normalized entry and calls this - nothing writes to Discord or the
---database directly.
---
---Expected shape (all fields optional except `action`):
---```
---{
---    action = 'stash_deposit',
---    player = { source, name, identifier, charName, job, jobLabel, grade, gradeLabel },
---    target = <same shape as player, for player<->player actions>,
---    item = { name, label, amount },
---    from = { id, type, slot, friendlyLabel },
---    to = { id, type, slot, friendlyLabel },
---    stash = 'stash id',
---    vehicle = 'plate',
---    shop = { id, label, price, currency },
---    recipe = { name, bench },
---    metadata = <raw item metadata table>,
---    coords = vector3,
---    note = 'free-form extra context',
---}
---```
---@param entry table
function Logger.Log(entry)
    if type(entry) ~= 'table' or not entry.action then return end

    local configKey = LOGGING_KEY[entry.action]
    if configKey and Config.Logging[configKey] == false then return end

    entry.timestamp = entry.timestamp or os.time()

    if entry.metadata then
        entry.metadataText = Utils.SanitizeMetadata(entry.metadata)
        entry.metadata = nil
    end

    local fingerprint = Utils.BuildFingerprint(entry)
    if isDuplicate(fingerprint) then
        Utils.DebugPrint('Duplicate action suppressed:', entry.action, fingerprint)
        return
    end

    Utils.DebugPrint(('Logging action "%s" for source %s.'):format(entry.action, tostring(entry.player and entry.player.source)))

    if Config.Storage == 'discord' or Config.Storage == 'both' then
        Discord.Log(entry)
    end

    if Config.Storage == 'database' or Config.Storage == 'both' then
        Database.Log(entry)
    end
end

-- Global alias matching the API shape requested for this resource, so
-- other parts of the codebase (or a future admin command/export) can call
-- LogInventoryAction({...}) directly without reaching into the Logger table.
function LogInventoryAction(entry)
    Logger.Log(entry)
end
