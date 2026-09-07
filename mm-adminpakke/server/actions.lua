-- ============================================================
--  mm-adminpakke V2 | server/actions.lua
--
--  Selve item-udleveringen. Modtager en allerede sikkerhedsvalideret
--  kurv (se server/security.lua) og udfører den via ox_inventory.
-- ============================================================

local Actions = {}

local function DebugPrint(fmt, ...)
    if not Config.Debug then return end
    print(('[mm-adminpakke] ' .. fmt):format(...))
end

--- Giver et enkelt item til en spiller via ox_inventory.
---@return boolean ok
---@return string reason
local function GiveItem(targetId, itemName, amount)
    if GetResourceState('ox_inventory') ~= 'started' then
        return false, 'ox_inventory er ikke tilgængeligt'
    end

    local ok, success = pcall(function()
        return exports.ox_inventory:AddItem(targetId, itemName, amount)
    end)

    if not ok then
        return false, 'ox_inventory fejlede: ' .. tostring(success)
    end
    if not success then
        return false, 'ox_inventory afviste item (fuldt inventar eller ugyldigt item)'
    end
    return true, 'ok'
end

--- Udfører en allerede-valideret kurv mod ét target.
---@param adminSrc number
---@param targetId number
---@param basket table
function Actions.GiveBasket(adminSrc, targetId, basket)
    local failedItems = {}
    local success = true

    for _, entry in ipairs(basket) do
        local ok, reason = GiveItem(targetId, entry.name, math.floor(entry.amount))
        if not ok then
            success = false
            failedItems[#failedItems + 1] = entry.name
            DebugPrint('Kunne ikke give %s til %s: %s', entry.name, targetId, reason)
        end
    end

    return success, failedItems
end

_G.AdminActions = Actions
