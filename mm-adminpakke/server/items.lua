-- ============================================================
--  mm-adminpakke V2 | server/items.lua
--
--  Bygger item-listen til NUI direkte fra ox_inventory's officielle
--  export - IKKE ved at regex-parse ox_inventory's kildefiler fra
--  disk (det gamle V1-system). Billed-opløsning følger ox_inventory's
--  egen, dokumenterede konvention:
--    1. Manuel override i Config.ImageOverrides (højeste prioritet)
--    2. item.client.image, hvis eksporten faktisk indeholder det
--    3. Fallback til '<item-navn>.png' (ox_inventory's standard)
--
--  Er et enkelt items billede stadig forkert efter dette (fx et
--  custom item med et helt andet filnavn end sit item-navn), er det
--  netop dét "Missing Images"-fanen i NUI'en er lavet til at afsløre,
--  så det kan rettes præcist via Config.ImageOverrides i stedet for
--  at gætte på flere mulige mappe-stier.
-- ============================================================

local Items = {}

local function DebugPrint(fmt, ...)
    if not Config.Debug then return end
    print(('[mm-adminpakke] ' .. fmt):format(...))
end

--- Bestemmer hvilken kategori et item hører til, ud fra
--- Config.Categories (første match vinder). Våben behandles altid
--- separat. Intet match -> Ukategoriseret (forsvinder aldrig).
local function ResolveCategory(name, isWeapon)
    if isWeapon then return 'vaaben' end

    local lower = name:lower()
    for _, cat in ipairs(Config.Categories) do
        for _, needle in ipairs(cat.match or {}) do
            if lower:find(needle, 1, true) then
                return cat.id
            end
        end
    end

    return 'ukategoriseret'
end

local function ResolveImage(name, itemData)
    local override = Config.ImageOverrides and Config.ImageOverrides[name]
    if override then return override end

    if type(itemData.client) == 'table' and type(itemData.client.image) == 'string' and itemData.client.image ~= '' then
        return itemData.client.image
    end

    return name .. '.png'
end

--- Bygger den fulde item-liste til NUI.
function Items.BuildList()
    local result = {}

    if GetResourceState('ox_inventory') ~= 'started' then
        print('^1[mm-adminpakke]^7 ox_inventory er ikke startet - kan ikke bygge item-listen.')
        return result
    end

    local ok, oxItems = pcall(function() return exports.ox_inventory:Items() end)
    if not ok or not oxItems then
        print('^1[mm-adminpakke]^7 Kunne ikke hente items fra ox_inventory: ' .. tostring(oxItems))
        return result
    end

    for name, data in pairs(oxItems) do
        local isWeapon = name:sub(1, 7) == 'weapon_'
        local image = ResolveImage(name, data)
        local category = ResolveCategory(name, isWeapon)

        result[#result + 1] = {
            name        = name,
            label       = data.label or name,
            weight      = data.weight or 0,
            description = data.description or '',
            image       = image,
            isWeapon    = isWeapon,
            category    = category,
            stack       = data.stack ~= false,
        }
    end

    table.sort(result, function(a, b)
        if a.isWeapon ~= b.isWeapon then return not a.isWeapon end
        return a.label:lower() < b.label:lower()
    end)

    DebugPrint('Byggede item-liste: %d items.', #result)
    return result
end

_G.AdminItems = Items
