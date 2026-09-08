-- ============================================================
-- MM-PolitiJob – server/actions.lua
-- GSR, ID-check, visitering + ox_inventory hook
-- ============================================================

local GSRData = {}  -- [identifier] = true/false + timeout

-- ── GSR ──────────────────────────────────────────────────────
RegisterNetEvent('mm_police:server:setGSR', function()
    local src        = source
    local identifier = SV.Framework.GetIdentifier(src)
    if not identifier then return end

    -- Undgå at resette timeout ved hvert skud
    if GSRData[identifier] then return end

    GSRData[identifier] = true
    SetTimeout(Config.GSRTimeout or 300000, function()
        GSRData[identifier] = nil
    end)
end)

-- ── GSR TEST ─────────────────────────────────────────────────
RegisterNetEvent('mm_police:server:gsrTest', function(targetId)
    local src      = source
    targetId       = tonumber(targetId)

    -- Validering
    if not SV.Framework.IsPolice(src) then return end
    if not targetId or not GetPlayerName(targetId) then return end
    if tonumber(src) == targetId then return end

    local tIdent  = SV.Framework.GetIdentifier(targetId)
    local result  = GSRData[tIdent] and 'Positiv' or 'Negativ'
    local ntype   = GSRData[tIdent] and 'error' or 'success'

    TriggerClientEvent('ox_lib:notify', src, {
        title       = '🔬 GSR Test',
        description = ('Resultat: **%s**'):format(result),
        type        = ntype,
        duration    = 6000,
    })
end)

-- ── ID CHECK ─────────────────────────────────────────────────
RegisterNetEvent('mm_police:server:idCheck', function(targetId)
    local src = source
    targetId  = tonumber(targetId)

    if not SV.Framework.IsPolice(src) then return end
    if not targetId or not GetPlayerName(targetId) then return end
    if tonumber(src) == targetId then return end

    local job, grade = SV.Framework.GetJob(targetId)
    local name       = SV.Framework.GetName(targetId)
    local identifier = SV.Framework.GetIdentifier(targetId)

    TriggerClientEvent('mm_police:client:idResult', src, {
        name       = name,
        identifier = identifier,
        job        = job or 'Ingen',
        grade      = grade or 0,
    })
end)

-- ── VISITERING ───────────────────────────────────────────────
RegisterNetEvent('mm_police:server:search', function(targetId)
    local src = source
    targetId  = tonumber(targetId)

    if not SV.Framework.IsPolice(src) then return end
    if not targetId or not GetPlayerName(targetId) then return end
    if tonumber(src) == targetId then return end

    -- FIX: Kun håndjernede spillere
    local tState = Player(targetId).state
    if not tState.isHandcuffed then
        SV_Notify(src, 'Fejl', 'Spilleren er ikke håndjernet.', 'error')
        return
    end

    -- FIX: sendte tidligere kun spillerens NAVN til klienten, som så
    -- kaldte exports.ox_inventory:openInventory('player', targetName) —
    -- ox_inventory forventer target-spillerens server-ID for 'player'
    -- inventory-typen, ikke et navn. Send derfor targetId i stedet.
    local targetName = SV.Framework.GetName(targetId)
    TriggerClientEvent('mm_police:client:searchResult', src, targetId, targetName)
end)

-- ox_inventory hook: kun politi kan åbne andres inventory via visitering
exports.ox_inventory:registerHook('openInventory', function(payload)
    local src    = payload.source
    local target = payload.target

    -- Kun politiet må åbne andres inventory via visitering
    if not SV.Framework.IsPolice(src) then return false end

    -- FIX: Target må ikke selv åbne (kun politiet kan trigge dette via server event)
    if target and target.type == 'player' and tonumber(target.id) then
        local tState = Player(tonumber(target.id)).state
        if not tState.isHandcuffed then return false end
    end

    return true
end, { inventoryFilter = { 'player' } })

-- ── LOADOUT ──────────────────────────────────────────────────
-- REWORK: våben blev tidligere givet via den rå GiveWeaponToPed
-- native (client/functions/loadout.lua's 'mm_police:client:giveWeapon').
-- Det går uden om ox_inventory's egen weapon-registrering, hvilket er
-- den sandsynlige årsag til at spillere "ikke nødvendigvis" fik det
-- våben de valgte: ox_inventory's periodiske weapon-validering fjerner
-- våben på ped'en som ikke findes i spillerens inventory-metadata.
-- Nu gives våben via exports.ox_inventory:AddItem med metadata
-- (ammo + components), som er den korrekte ox_inventory-vej, og
-- attachments (Config.Attachments) bliver dermed rent faktisk
-- appliceret på våbnet, ikke kun vist i NUI'et.
local function GenerateSerial()
    return ('POL-%06d'):format(math.random(0, 999999))
end

RegisterNetEvent('mm_police:server:giveLoadout', function(loadoutName)
    local src = source

    -- Validering: job + gyldigt loadout/kategori
    if not SV.Framework.IsPolice(src) then
        if Config.Debug then
            print(('[MM-PolitiJob] %s forsøgte at hente loadout uden politi-job.'):format(src))
        end
        return
    end

    local loadout = (type(loadoutName) == 'string') and Config.Loadouts[loadoutName]
    if not loadout then
        SV_Notify(src, 'Fejl', 'Ukendt loadout.', 'error')
        return
    end
    if loadout.isShop then return end  -- Shop åbnes client-side

    -- Giv våben (med ammo + components) via ox_inventory
    for _, weapon in ipairs(loadout.weapons or {}) do
        local ammo       = (Config.WeaponAmmo and Config.WeaponAmmo[weapon]) or Config.DefaultAmmo
        local components = Config.Attachments and Config.Attachments[weapon]

        local added = exports.ox_inventory:AddItem(src, weapon, 1, {
            ammo       = ammo,
            durability = 100,
            serial     = GenerateSerial(),
            registered = true,
            components = components and components or nil,
        })

        if Config.Debug then
            print(('[MM-PolitiJob] giveLoadout: %s -> %s (added=%s, ammo=%d, components=%d)')
                :format(src, weapon, tostring(added), ammo, components and #components or 0))
        end
    end

    -- Giv items
    for _, item in ipairs(loadout.items or {}) do
        exports.ox_inventory:AddItem(src, item.name, item.amount or 1)
    end

    SV_Notify(src, 'Loadout', ('Du fik loadout: %s'):format(loadoutName), 'success')
end)

-- ── IMPOUND KØRETØJ ────────────────────────────────────────────
-- FIX: dette event var tidligere fejlagtigt implementeret i
-- client/functions/Interaktion.lua (et CLIENT-script) og brugte
-- 'source', som ikke er defineret client-side. Eventet ville derfor
-- enten fejle stille eller aldrig kunne trigges korrekt. Flyttet
-- hertil, hvor det hører til, og med korrekt server-side validering.
RegisterNetEvent('mm_police:server:impoundVehicle', function(plate, reason)
    local src = source

    if not SV.Framework.IsPolice(src) then return end
    if not plate or type(plate) ~= 'string' then return end

    if Config.Debug then
        print(('[MM-PolitiJob] %s impoundede %s (grund: %s)')
            :format(src, plate, tostring(reason)))
    end

    -- HER KAN DU SENERE GEMME I DATABASE (fx en impound-log tabel)
end)