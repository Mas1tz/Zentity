-- ============================================================
--  mm-adminpakke V2 | server/main.lua
--
--  Orkestrerer de andre server-moduler: modtager events fra
--  klienten, validerer permissions/rate-limit, og sender svar
--  tilbage. Alt sikkerhedskritisk er allerede foretaget af
--  server/security.lua - denne fil kalder blot ind i den.
-- ============================================================

local function DebugPrint(fmt, ...)
    if not Config.Debug then return end
    print(('[mm-adminpakke] ' .. fmt):format(...))
end

local function BuildCategoryPayload()
    local cats = {}
    for _, cat in ipairs(Config.Categories) do
        cats[#cats + 1] = { id = cat.id, label = cat.label, icon = cat.icon }
    end
    return cats
end

RegisterNetEvent('mm-adminpakke:server:requestOpen', function()
    local src = source

    if not Security.IsAdmin(src) then
        Config.Notify(src, 'Du har ikke tilladelse til at bruge dette.', 'error')
        print(('^1[mm-adminpakke SIKKERHED]^7 Uautoriseret åbningsforsøg fra src:%s'):format(src))
        return
    end

    if Security.CheckRateLimit(src) then
        Config.Notify(src, 'Du sender forespørgsler for hurtigt.', 'error')
        return
    end

    TriggerClientEvent('mm-adminpakke:client:openUI', src, {
        items          = AdminItems.BuildList(),
        players        = AdminPlayers.GetList(),
        imageBasePath  = Config.ImageBasePath,
        blacklist      = Config.BlacklistedItems or {},
        categories     = BuildCategoryPayload(),
        uncategorized  = { id = 'ukategoriseret', label = Config.UncategorizedLabel, icon = Config.UncategorizedIcon },
        weaponsCategory = { id = 'vaaben', label = Config.WeaponsLabel, icon = Config.WeaponsIcon },
        maxItemAmount  = Config.MaxItemAmount,
        itemsPerPage   = Config.ItemsPerPage,
        theme          = Config.Theme,
        debug          = Config.Debug,
        missingImageManagerEnabled = Config.MissingImageManager.Enabled,
    })
end)

RegisterNetEvent('mm-adminpakke:server:refreshPlayers', function()
    local src = source
    if not Security.IsAdmin(src) then return end
    if Security.CheckRateLimit(src) then return end

    TriggerClientEvent('mm-adminpakke:client:playersUpdate', src, AdminPlayers.GetList())
end)

RegisterNetEvent('mm-adminpakke:server:giveBasket', function(targetId, basket)
    local src = source

    if not Security.IsAdmin(src) then
        Config.Notify(src, 'Uautoriseret.', 'error')
        print(('^1[mm-adminpakke SIKKERHED]^7 Uautoriseret give-forsøg fra src:%s'):format(src))
        return
    end

    if Security.CheckRateLimit(src) then
        Config.Notify(src, 'Du sender forespørgsler for hurtigt.', 'error')
        return
    end

    local targetValid, tId = Security.ValidateTarget(targetId)
    if not targetValid then
        Config.Notify(src, 'Ugyldig spiller.', 'error')
        TriggerClientEvent('mm-adminpakke:client:basketSent', src, false, 'Ugyldig spiller.')
        return
    end

    local basketValid, basketErr = Security.ValidateBasket(basket)
    if not basketValid then
        Config.Notify(src, 'Kurv-fejl: ' .. basketErr, 'error')
        print(('^1[mm-adminpakke SIKKERHED]^7 Ugyldig kurv fra src:%s | Fejl: %s'):format(src, basketErr))
        TriggerClientEvent('mm-adminpakke:client:basketSent', src, false, basketErr)
        return
    end

    local success, failedItems = AdminActions.GiveBasket(src, tId, basket)

    local adminName  = GetPlayerName(src) or tostring(src)
    local targetName = GetPlayerName(tId) or tostring(tId)
    AdminLogs.Log(adminName, src, targetName, tId, basket)

    if success then
        Config.Notify(src, ('Gav succesfuldt %d varetype(r) til %s'):format(#basket, targetName), 'success')
        Config.Notify(tId, 'Du har modtaget items fra en admin.', 'inform')
    else
        Config.Notify(src, 'Nogle items fejlede: ' .. table.concat(failedItems, ', '), 'error')
    end

    TriggerClientEvent('mm-adminpakke:client:basketSent', src, success, not success and table.concat(failedItems, ', ') or nil)
end)

lib.callback.register('mm-adminpakke:server:getPlayerProfile', function(src, targetId)
    if not Security.IsAdmin(src) then return nil end
    local id = tonumber(targetId)
    if not id or not GetPlayerName(id) then return nil end
    return AdminPlayers.GetProfile(id)
end)
