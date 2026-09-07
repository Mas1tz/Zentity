-- ============================================================
--  mm-adminpakke V2 | server/security.lua
--
--  Al sikkerhedskritisk validering samlet ét sted: permissions,
--  rate-limiting, item/mængde/target-validering. Klienten/NUI'en
--  bliver ALDRIG stolet på for nogen af disse beslutninger.
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

local Security = {}

local function DebugPrint(fmt, ...)
    if not Config.Debug then return end
    print(('[mm-adminpakke] ' .. fmt):format(...))
end

-- ------------------------------------------------------------------
--  PERMISSIONS
-- ------------------------------------------------------------------
function Security.IsAdmin(src)
    if type(src) ~= 'number' then return false end

    if Config.UseAcePermission then
        return IsPlayerAceAllowed(src, Config.AcePermission)
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end

    local group = xPlayer.getGroup and xPlayer.getGroup() or nil
    if not group then return false end

    for _, allowed in ipairs(Config.AllowedGroups) do
        if group == allowed then return true end
    end
    return false
end

-- ------------------------------------------------------------------
--  RATE LIMIT
-- ------------------------------------------------------------------
local rateLimitStore = {} -- [src] = { count, resetAt }

function Security.CheckRateLimit(src)
    if not Config.RateLimit.Enabled then return false end

    local now = os.time()
    local entry = rateLimitStore[src]

    if not entry or now >= entry.resetAt then
        rateLimitStore[src] = { count = 1, resetAt = now + Config.RateLimit.WindowSeconds }
        return false
    end

    entry.count = entry.count + 1
    if entry.count > Config.RateLimit.MaxRequests then
        print(('^1[mm-adminpakke SIKKERHED]^7 Rate limit ramt af src:%s'):format(src))
        return true
    end

    return false
end

-- Ryd gamle rate-limit-entries for at undgå en langsom memory leak.
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for src, entry in pairs(rateLimitStore) do
            if now >= entry.resetAt then
                rateLimitStore[src] = nil
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    rateLimitStore[source] = nil
end)

-- ------------------------------------------------------------------
--  ITEM-VALIDERING
-- ------------------------------------------------------------------
local itemCache = nil

local function BuildItemCache()
    if GetResourceState('ox_inventory') ~= 'started' then
        itemCache = {}
        return
    end
    local ok, oxItems = pcall(function() return exports.ox_inventory:Items() end)
    itemCache = (ok and oxItems) or {}
    DebugPrint('Item-cache bygget til validering (%d items).', (function()
        local n = 0
        for _ in pairs(itemCache) do n = n + 1 end
        return n
    end)())
end

CreateThread(function()
    Wait(1000)
    BuildItemCache()
end)

AddEventHandler('onResourceStart', function(name)
    if name == 'ox_inventory' then
        Wait(500)
        BuildItemCache()
    end
end)

local blacklistSet = nil
local function GetBlacklistSet()
    if not blacklistSet then
        blacklistSet = {}
        for _, name in ipairs(Config.BlacklistedItems or {}) do
            blacklistSet[name] = true
        end
    end
    return blacklistSet
end

--- Validér at et item findes i ox_inventory og ikke er sortlistet.
function Security.IsValidItem(itemName)
    if type(itemName) ~= 'string' then return false end
    if #itemName == 0 or #itemName > 64 then return false end
    if itemName:match('[^%w%-_]') then return false end
    if GetBlacklistSet()[itemName] then return false end

    if not itemCache then return false end -- fail-closed: ingen cache = intet er gyldigt
    return itemCache[itemName] ~= nil
end

--- Validér og normalisér et antal. Dette er DEN autoritative grænse -
--- klienten kan sende hvad som helst, kun dette tal betyder noget.
function Security.ValidateAmount(amount)
    local num = tonumber(amount)
    if not num then return false, 0 end
    num = math.floor(num)
    if num < 1 then return false, 0 end
    if num > Config.MaxItemAmount then return false, 0 end
    return true, num
end

--- Validér en hel kurv (liste af {name, amount}).
function Security.ValidateBasket(basket)
    if type(basket) ~= 'table' then return false, 'Ugyldigt kurv-format' end
    if #basket == 0 then return false, 'Kurven er tom' end
    if #basket > Config.MaxBasketItems then return false, 'For mange varetyper i kurven' end

    local totalAmount = 0
    local seen = {}

    for i, entry in ipairs(basket) do
        if type(entry) ~= 'table' then return false, 'Ugyldigt kurv-item ved index ' .. i end
        if not entry.name or not entry.amount then
            return false, 'Mangler navn eller antal i kurv-item'
        end

        if not Security.IsValidItem(entry.name) then
            return false, 'Ugyldigt eller sortlistet item: ' .. tostring(entry.name)
        end

        local valid, amount = Security.ValidateAmount(entry.amount)
        if not valid then
            return false, ('Ugyldigt antal for %s (max %d)'):format(entry.name, Config.MaxItemAmount)
        end

        if seen[entry.name] then
            return false, 'Duplikeret item i kurven: ' .. entry.name
        end
        seen[entry.name] = true

        totalAmount = totalAmount + amount
        if totalAmount > Config.MaxBasketTotalAmount then
            return false, 'Det samlede antal i kurven overskrider grænsen'
        end
    end

    return true, 'ok'
end

--- Validér et target server-id.
function Security.ValidateTarget(targetId)
    local id = tonumber(targetId)
    if not id then return false, 0 end
    if not GetPlayerName(id) then return false, 0 end
    return true, id
end

_G.Security = Security
