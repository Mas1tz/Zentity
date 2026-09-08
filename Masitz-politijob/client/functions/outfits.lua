-- ============================================================
-- MM-PolitiJob – client/functions/outfits.lua  (NY)
-- Politi-uniformer via ox_lib context menu på Config.OutfitLocation.
--
-- Der findes intet eksisterende appearance-resource (fx
-- illenium-appearance) nogen steder i denne resource at hooke ind
-- i, så outfits appliceres direkte via FiveM's egne ped-component
-- natives. Component-numrene i Config.Outfits matcher derfor
-- standard GTA ped-components (se kommentar i config.lua).
-- ============================================================

local COMPONENT = {
    arms       = 3,
    torso      = 11, -- "jakke"/top-lag
    pants      = 4,
    undershirt = 8,
    shoes      = 6,
    decals     = 10,
}

local PROP = {
    helmet  = 0,
    glasses = 1,
}

local function ApplyOutfit(components)
    local ped = cache.ped

    for field, componentId in pairs(COMPONENT) do
        local drawable = components[field]
        if drawable and drawable >= 0 then
            SetPedComponentVariation(ped, componentId, drawable, 0, 0)
        end
    end

    for field, propId in pairs(PROP) do
        local drawable = components[field]
        if drawable and drawable >= 0 then
            SetPedPropIndex(ped, propId, drawable, 0, true)
        else
            ClearPedProp(ped, propId)
        end
    end
end

local function BuildOutfitDetailOptions(outfit)
    local c = outfit.components or {}

    return {
        {
            title    = 'Component-numre',
            readOnly = true,
            metadata = {
                { label = 'Jakke',      value = c.torso      or -1 },
                { label = 'Bukser',     value = c.pants      or -1 },
                { label = 'Sko',        value = c.shoes      or -1 },
                { label = 'Undershirt', value = c.undershirt or -1 },
                { label = 'Arme',       value = c.arms       or -1 },
                { label = 'Decals',     value = c.decals     or -1 },
                { label = 'Hat',        value = c.helmet     or -1 },
                { label = 'Briller',    value = c.glasses    or -1 },
            },
        },
        {
            title    = '👕 Tag Outfit På',
            icon     = 'shirt',
            onSelect = function()
                ApplyOutfit(c)
                lib.notify({
                    title       = 'Outfit',
                    description = ('Du har taget %s på.'):format(outfit.label),
                    type        = 'success',
                    position    = 'center-right',
                })
            end,
        },
    }
end

local function OpenOutfitMenu()
    if not MM.Framework.IsPolice() then
        lib.notify({
            title       = 'Adgang nægtet',
            description = 'Du har ikke adgang til politiets uniformer.',
            type        = 'error',
            position    = 'center-right',
        })
        return
    end

    local options = {}
    for i, outfit in ipairs(Config.Outfits or {}) do
        options[#options + 1] = {
            title = outfit.label,
            icon  = 'fa-solid fa-shirt',
            arrow = true,
            menu  = 'mm_outfit_detail_' .. i,
        }

        lib.registerContext({
            id      = 'mm_outfit_detail_' .. i,
            title   = outfit.label,
            menu    = 'mm_outfits_main',
            options = BuildOutfitDetailOptions(outfit),
        })
    end

    lib.registerContext({
        id      = 'mm_outfits_main',
        title   = '👮 Politiuniformer',
        options = options,
    })
    lib.showContext('mm_outfits_main')
end

CreateThread(function()
    if not Config.OutfitLocation then return end

    exports.ox_target:addSphereZone({
        coords = Config.OutfitLocation,
        radius = 1.5,
        debug  = Config.Debug or false,
        options = {
            {
                name  = 'mm_outfit_menu',
                label = 'Politiuniformer',
                icon  = 'fa-solid fa-shirt',
                distance = 2.0,
                canInteract = function()
                    return MM.Framework.IsPolice()
                end,
                onSelect = function()
                    OpenOutfitMenu()
                end,
            }
        }
    })

    if Config.Debug then
        print('[MM-PolitiJob] Outfit target-zone oprettet.')
    end
end)
