-- ============================================================
--  Masitz-InventoryLogs | server/hooks.lua
--  Registers every ox_inventory server hook that can reliably be
--  used for audit logging (verified against ox_inventory 2.47.9
--  source - modules/hooks/server.lua, modules/inventory/server.lua,
--  modules/shops/server.lua, modules/crafting/server.lua, server.lua).
--
--  Hooks run SYNCHRONOUSLY inside ox_inventory's own pcall and
--  BLOCK the calling function until they return. Every handler here
--  therefore only does cheap synchronous work (ESX lookups, native
--  calls, table lookups) and hands off to Logger.Log, which itself
--  only does a cheap table insert before returning - all network/DB
--  I/O happens later on a separate thread (see discord.lua/database.lua).
--
--  We deliberately do NOT hook `createItem`: it fires on every single
--  item creation (buy, craft, give, admin AddItem, drops, ...), so
--  using it for general-purpose logging would duplicate everything
--  already covered by swapItems/buyItem/craftItem below. The one
--  gap it would have filled - server console commands / other
--  resources calling exports.ox_inventory:AddItem|RemoveItem|SetItem
--  directly (e.g. /additem) - has no dedicated hook in this version
--  of ox_inventory and is not logged. See README.md "Known limitations".
-- ============================================================

local function safeItemLabel(itemName)
    if not itemName then return nil end

    local ok, item = pcall(function()
        return exports.ox_inventory:Items(itemName)
    end)

    if ok and type(item) == 'table' and item.label then
        return item.label
    end

    return itemName
end

local function friendlyInventoryLabel(id, invType)
    if invType ~= 'stash' and invType ~= 'temp' then return nil end
    if id == nil then return nil end

    local ok, inv = pcall(function()
        return exports.ox_inventory:GetInventory(id)
    end)

    if ok and type(inv) == 'table' and inv.label and inv.label ~= tostring(id) then
        return inv.label
    end

    return nil
end

---@param id string|number|nil
---@param invType string?
---@param slotField table|number|nil
---@return table
local function buildSide(id, invType, slotField)
    local normalized = Utils.NormalizeSlotField(slotField)
    return {
        id = id,
        type = invType,
        slot = normalized.slot,
        friendlyLabel = friendlyInventoryLabel(id, invType),
    }
end

local function runHook(name, fn)
    return function(payload)
        local ok, err = pcall(fn, payload)
        if not ok then
            Utils.Warn(('Hook handler for "%s" errored: %s'):format(name, tostring(err)))
        end
    end
end

-- Registration is deferred and guarded behind a resource-state check so
-- this never races ox_inventory's own startup, even though the fxmanifest
-- `dependencies` block should already guarantee start order.
local pendingRegistrations = {}

local function deferRegisterHook(event, name, fn)
    pendingRegistrations[#pendingRegistrations + 1] = { event = event, handler = runHook(name, fn) }
end

-- ------------------------------------------------------------
--  swapItems - the single hook behind give/drop/pickup/stash/
--  trunk/glovebox/evidence/dumpster/container/split/merge/move.
--  Classification is driven entirely by the `action` field and
--  `fromType`/`toType`, both supplied directly by ox_inventory -
--  we never have to guess an inventory's type ourselves.
-- ------------------------------------------------------------

---@param payload table
---@return string action
---@return string|number toInventory  (resolved - handles the drop "newdrop" placeholder)
local function classifySwap(payload)
    local action = payload.action
    local fromType = payload.fromType
    local toType = payload.toType
    local fromInv = payload.fromInventory
    local toInv = payload.toInventory

    -- ox_inventory's dropItem() sends toInventory = literal "newdrop" and the
    -- real id separately as payload.dropId (verified in modules/inventory/server.lua).
    if toType == 'drop' and payload.dropId then
        toInv = payload.dropId
    end

    if action == 'give' then
        return 'give', toInv
    end

    if toType == 'drop' then
        return 'drop', toInv
    end

    if fromType == 'drop' then
        return 'pickup', toInv
    end

    if fromInv ~= nil and toInv ~= nil and tostring(fromInv) == tostring(toInv) then
        if action == 'stack' then return 'inventory_stack', toInv end

        local fromSlotData = Utils.NormalizeSlotField(payload.fromSlot)
        if payload.count and fromSlotData.count and payload.count < fromSlotData.count then
            return 'split_stack', toInv
        end

        return 'move_slot', toInv
    end

    if fromType == 'stash' or toType == 'stash' then
        return (toType == 'stash' and 'stash_deposit' or 'stash_withdraw'), toInv
    end

    if fromType == 'trunk' or toType == 'trunk' then
        return (toType == 'trunk' and 'trunk_deposit' or 'trunk_withdraw'), toInv
    end

    if fromType == 'glovebox' or toType == 'glovebox' then
        return (toType == 'glovebox' and 'glovebox_deposit' or 'glovebox_withdraw'), toInv
    end

    if fromType == 'policeevidence' or toType == 'policeevidence' then
        return (toType == 'policeevidence' and 'evidence_deposit' or 'evidence_withdraw'), toInv
    end

    if fromType == 'dumpster' or toType == 'dumpster' then
        return (toType == 'dumpster' and 'dumpster_deposit' or 'dumpster_retrieve'), toInv
    end

    if fromType == 'container' or toType == 'container' then
        return (toType == 'container' and 'container_store' or 'container_retrieve'), toInv
    end

    if action == 'swap' then return 'inventory_swap', toInv end
    if action == 'stack' then return 'inventory_stack', toInv end

    return 'inventory_transfer', toInv
end

local function handleSwapItems(payload)
    local action, toInv = classifySwap(payload)

    local fromSlotData = Utils.NormalizeSlotField(payload.fromSlot)
    local itemName = fromSlotData.name or payload.itemName
    if not itemName then return end -- no identifiable item, nothing safe to log

    local player = Framework.GetPlayerInfo(payload.source)

    local entry = {
        action = action,
        player = player,
        item = {
            name = itemName,
            label = safeItemLabel(itemName),
            amount = payload.count or fromSlotData.count,
        },
        from = buildSide(payload.fromInventory, payload.fromType, payload.fromSlot),
        to = buildSide(toInv, payload.toType, payload.toSlot),
        metadata = fromSlotData.metadata,
        timestamp = os.time(),
    }

    -- Target player (give, or any transfer where the other side is a
    -- different player's inventory - e.g. trading UIs built on ox_inventory).
    if action == 'give' or (payload.fromType == 'player' and payload.toType == 'player') then
        local targetId = tonumber(toInv)
        if targetId and targetId ~= payload.source then
            entry.target = Framework.GetPlayerInfo(targetId)
        end
    end

    if payload.fromType == 'trunk' or payload.fromType == 'glovebox' then
        entry.vehicle = Utils.ExtractPlate(tostring(payload.fromInventory), payload.fromType)
    elseif payload.toType == 'trunk' or payload.toType == 'glovebox' then
        entry.vehicle = Utils.ExtractPlate(tostring(toInv), payload.toType)
    end

    if payload.fromType == 'stash' then
        entry.stash = tostring(payload.fromInventory)
    elseif payload.toType == 'stash' then
        entry.stash = tostring(toInv)
    end

    if Config.PlayerInfo.includeCoords and (action == 'drop' or action == 'pickup') then
        entry.coords = Utils.GetPlayerCoords(payload.source)
    end

    Logger.Log(entry)
end

deferRegisterHook('swapItems', 'swapItems', handleSwapItems)

-- ------------------------------------------------------------
--  buyItem - shop purchases
-- ------------------------------------------------------------

local function handleBuyItem(payload)
    local fromSlotData = Utils.NormalizeSlotField(payload.fromSlot)
    local itemName = payload.itemName or fromSlotData.name
    if not itemName then return end

    local shopId = payload.shopType
    if payload.shopId then
        shopId = ('%s %s'):format(payload.shopType, payload.shopId)
    end

    Logger.Log({
        action = 'shop_purchase',
        player = Framework.GetPlayerInfo(payload.source),
        item = {
            name = itemName,
            label = safeItemLabel(itemName),
            amount = payload.count,
        },
        to = buildSide(payload.toInventory, 'player', payload.toSlot),
        shop = {
            id = shopId,
            label = payload.shopType,
            price = payload.totalPrice or payload.price,
            currency = payload.currency,
        },
        metadata = payload.metadata,
        coords = Config.PlayerInfo.includeCoords and Utils.GetPlayerCoords(payload.source) or nil,
    })
end

deferRegisterHook('buyItem', 'buyItem', handleBuyItem)

-- ------------------------------------------------------------
--  craftItem - crafting bench
--  Note: this hook fires once the recipe/ingredients/permissions
--  have been validated, but BEFORE the client-side crafting
--  animation finishes. ox_inventory has no post-completion hook in
--  this version, so in the rare case a player cancels the crafting
--  animation client-side, ingredients are never actually consumed
--  even though this log entry was already produced. Documented in
--  README.md "Known limitations" - we do not invent a workaround.
-- ------------------------------------------------------------

local function formatIngredients(ingredients)
    if type(ingredients) ~= 'table' then return nil end

    local parts = {}
    for name, needs in pairs(ingredients) do
        if type(needs) == 'number' and needs < 1 then
            parts[#parts + 1] = ('%s (durability -%d%%)'):format(safeItemLabel(name) or name, math.floor(needs * 100))
        else
            parts[#parts + 1] = ('%s x%s'):format(safeItemLabel(name) or name, tostring(needs))
        end
    end

    if #parts == 0 then return nil end
    return table.concat(parts, ', ')
end

local function handleCraftItem(payload)
    local recipe = payload.recipe
    if type(recipe) ~= 'table' or not recipe.name then return end

    local amount = (type(recipe.count) == 'number' and recipe.count) or 1

    Logger.Log({
        action = 'craft',
        player = Framework.GetPlayerInfo(payload.source),
        item = {
            name = recipe.name,
            label = safeItemLabel(recipe.name),
            amount = amount,
        },
        to = buildSide(payload.toInventory, 'player', payload.toSlot),
        recipe = {
            name = safeItemLabel(recipe.name) or recipe.name,
            bench = tostring(payload.benchId),
        },
        metadata = recipe.metadata,
        note = formatIngredients(recipe.ingredients),
        coords = Config.PlayerInfo.includeCoords and Utils.GetPlayerCoords(payload.source) or nil,
    })
end

deferRegisterHook('craftItem', 'craftItem', handleCraftItem)

-- ------------------------------------------------------------
--  openInventory - bonus: stash/trunk/glovebox/container/evidence
--  ACCESS auditing, independent of whether items actually moved.
--  Off by default (Config.Logging.openInventoryAccess) - fires on
--  every single open, which is high volume.
-- ------------------------------------------------------------

local NON_AUDITABLE_OPEN_TYPES = {
    player = true,
    otherplayer = true,
}

local function handleOpenInventory(payload)
    if NON_AUDITABLE_OPEN_TYPES[payload.inventoryType] then return end

    Logger.Log({
        action = 'open_inventory',
        player = Framework.GetPlayerInfo(payload.source),
        to = buildSide(payload.inventoryId, payload.inventoryType, payload.slot),
        vehicle = Utils.ExtractPlate(tostring(payload.inventoryId), payload.inventoryType),
        stash = payload.inventoryType == 'stash' and tostring(payload.inventoryId) or nil,
        coords = Config.PlayerInfo.includeCoords and Utils.GetPlayerCoords(payload.source) or nil,
    })
end

deferRegisterHook('openInventory', 'openInventory', handleOpenInventory)

-- ------------------------------------------------------------
--  usingItem - bonus: item consumption/use. Off by default, very
--  high volume (eating, drinking, bandages, etc).
-- ------------------------------------------------------------

local function handleUsingItem(payload)
    local item = payload.item
    if type(item) ~= 'table' or not item.name then return end

    Logger.Log({
        action = 'use_item',
        player = Framework.GetPlayerInfo(payload.source),
        item = {
            name = item.name,
            label = safeItemLabel(item.name),
            amount = 1,
        },
        from = buildSide(payload.inventoryId, 'player', item.slot),
        metadata = item.metadata,
    })
end

deferRegisterHook('usingItem', 'usingItem', handleUsingItem)

-- ------------------------------------------------------------
--  openShop - bonus: shop menu opened (not a purchase). Off by
--  default - shopPurchase already covers the actual transactions.
-- ------------------------------------------------------------

local function handleOpenShop(payload)
    Logger.Log({
        action = 'open_shop',
        player = Framework.GetPlayerInfo(payload.source),
        shop = {
            id = payload.shopId and ('%s %s'):format(payload.shopType, payload.shopId) or payload.shopType,
            label = payload.label or payload.shopType,
        },
        coords = Config.PlayerInfo.includeCoords and Utils.GetPlayerCoords(payload.source) or nil,
    })
end

deferRegisterHook('openShop', 'openShop', handleOpenShop)

-- ------------------------------------------------------------
--  Guarded registration
-- ------------------------------------------------------------

CreateThread(function()
    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(250)
    end

    for i = 1, #pendingRegistrations do
        local reg = pendingRegistrations[i]
        exports.ox_inventory:registerHook(reg.event, reg.handler)
    end

    Utils.DebugPrint(('%d ox_inventory hooks registered.'):format(#pendingRegistrations))
end)
