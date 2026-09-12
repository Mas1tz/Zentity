-- ══════════════════════════════════════════════════════════
--  INVENTORY ABSTRACTION — mm-christmas
--
--  Primær integration: ox_inventory. Alle item-operationer går
--  gennem denne fil, så resten af koden aldrig kalder
--  exports.ox_inventory direkte - og aldrig antager stiltiende at et
--  item findes eller at en operation lykkedes.
-- ══════════════════════════════════════════════════════════

Inventory = {}

local function ox()
    return exports.ox_inventory
end

function Inventory.Available()
    return GetResourceState('ox_inventory') == 'started'
end

-- Returnerer altid et tal (0 hvis ox_inventory ikke er tilgængeligt) -
-- aldrig nil, så kaldere ikke behøver at nil-checke ved hver brug.
function Inventory.GetCount(src, item)
    if not Inventory.Available() then return 0 end
    local ok, count = pcall(function() return ox():GetItemCount(src, item) end)
    if not ok then
        Shared.Warn(('GetItemCount Lua-fejl for "%s": %s'):format(item, tostring(count)))
        return 0
    end
    return count or 0
end

function Inventory.HasItem(src, item, amount)
    return Inventory.GetCount(src, item) >= (amount or 1)
end

function Inventory.GetSlot(src, slot)
    if not Inventory.Available() then return nil end
    local ok, data = pcall(function() return ox():GetSlot(src, slot) end)
    if not ok then return nil end
    return data
end

-- Giver et item. Returnerer true/false - kaldere SKAL tjekke dette og
-- rulle enhver forudgående betaling/fjernelse tilbage ved false, så
-- spilleren aldrig betaler/mister noget uden at modtage varen.
function Inventory.GiveItem(src, item, amount, metadata)
    amount = Shared.ToPositiveInt(amount, 1)
    if amount <= 0 then return false end

    if Inventory.Available() then
        local ok, result = pcall(function() return ox():AddItem(src, item, amount, metadata) end)
        if ok and result then
            return true
        elseif ok then
            Shared.Warn(('GiveItem fejlede: item "%s" findes sandsynligvis ikke i ox_inventory items.lua, eller inventory er fuldt.'):format(item))
        else
            Shared.Warn(('GiveItem Lua-fejl for item "%s": %s'):format(item, tostring(result)))
        end
        return false
    end

    -- ox_inventory kører ikke — fald tilbage til framework-inventory hvis muligt.
    return Framework.GiveItemFallback(src, item, amount)
end

-- Fjerner et item. `slot` er valgfri (uden slot fjernes fra første
-- matchende stak). Returnerer true/false.
function Inventory.RemoveItem(src, item, amount, slot)
    amount = Shared.ToPositiveInt(amount, 1)
    if amount <= 0 then return false end

    if not Inventory.Available() then
        Shared.Warn(('RemoveItem kaldt for "%s" men ox_inventory kører ikke - kan ikke fjerne sikkert.'):format(item))
        return false
    end

    local ok, result = pcall(function()
        if slot then
            -- ox_inventory signatur: RemoveItem(inv, item, count, metadata, slot)
            return ox():RemoveItem(src, item, amount, nil, slot)
        end
        return ox():RemoveItem(src, item, amount)
    end)

    if not ok then
        Shared.Warn(('RemoveItem Lua-fejl for item "%s": %s'):format(item, tostring(result)))
        return false
    end

    return result and true or false
end
