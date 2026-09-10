-- ============================================================
--  kc_mdt | server/sv_data.lua
--  Charges, laws + static-data caching
--
--  Lovbog (Config.Laws) og Bødeskema (Config.Fines) leveres nu
--  direkte fra config.lua (§5, §7, §30) i stedet for databasen,
--  så admin kan tilføje/fjerne/redigere uden SQL — se config.lua.
-- ============================================================

-- In-memory cache af de fladlagte (flattened) config-lister.
-- Bygges kun én gang pr. resource-start (config ændrer sig ikke i runtime).
local flatCache = {
    charges = nil,
    laws    = nil,
}

local function buildCharges()
    if flatCache.charges then return flatCache.charges end
    local out = {}
    for category, list in pairs(Config.Fines or {}) do
        for _, f in ipairs(list) do
            out[#out+1] = {
                category = category,
                label    = f.label,
                fine     = f.fine or 0,
                jail     = f.jail or 0,
                law_ref  = f.lawRef,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return a.label < b.label
    end)
    flatCache.charges = out
    return out
end

local function buildLaws()
    if flatCache.laws then return flatCache.laws end
    local out = {}
    for _, cat in pairs(Config.Laws or {}) do
        for _, e in ipairs(cat.entries or {}) do
            out[#out+1] = {
                book      = cat.book,
                paragraph = e.paragraph,
                title     = e.title,
                text      = e.text,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.book ~= b.book then return a.book < b.book end
        return a.paragraph < b.paragraph
    end)
    flatCache.laws = out
    return out
end

-- ═══════════════════════════════════════════════════════════
--  CHARGES (Bødeskema)
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:getCharges', function(src)
    if not KCS.requireSession(src) then return {} end
    return buildCharges()
end)

-- ═══════════════════════════════════════════════════════════
--  LAWS (Lovbog)
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:getLaws', function(src, query)
    if not KCS.requireSession(src) then return {} end
    local all = buildLaws()
    if query and #query > 1 then
        local n = KC.safeStr(query, 100):lower()
        local out = {}
        for _, l in ipairs(all) do
            if (l.title and l.title:lower():find(n, 1, true))
            or (l.text and l.text:lower():find(n, 1, true))
            or (l.paragraph and l.paragraph:lower():find(n, 1, true)) then
                out[#out+1] = l
            end
        end
        return out
    end
    return all
end)

-- ═══════════════════════════════════════════════════════════
--  STATIC CONFIG — én callback der sender hele UI/menu/kode-opsætningen
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:getStaticConfig', function(src)
    if not KCS.requireSession(src) then return nil end
    return {
        units            = Config.PatrolUnits,
        riskLevels       = Config.RiskLevels,
        radioCodes       = Config.RadioCodes,
        seizedCategories = Config.SeizedCategories,
        images           = Config.Images,
        permissions      = Config.Permissions,
        menus            = Config.Menus,
        ui               = Config.UI,
        dispatch         = Config.Dispatch,
        rightsPhrases    = Config.RightsPhrases,
        corruption       = Config.CorruptionSection,
        weapons          = Config.WeaponRegulation,
    }
end)
