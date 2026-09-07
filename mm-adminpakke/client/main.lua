-- ============================================================
--  mm-adminpakke V2 | client/main.lua
--
--  NUI-bro: åbner/lukker UI'et, videresender NUI-callbacks til
--  serveren, og holder tablet-prop'en (client/tablet.lua) i sync med
--  om UI'et rent faktisk er åbent. Ingen permanente Wait(0)-loops -
--  ESC-lytteren kører KUN mens UI'et er åbent.
-- ============================================================

local function DebugPrint(fmt, ...)
    if not Config.Debug then return end
    print(('[mm-adminpakke] ' .. fmt):format(...))
end

local isOpen = false
local escWatcherActive = false

-- ------------------------------------------------------------------
--  ÅBNE / LUKKE
-- ------------------------------------------------------------------

local function StartEscWatcher()
    if escWatcherActive then return end
    escWatcherActive = true

    CreateThread(function()
        while isOpen do
            if IsControlJustReleased(0, 200) then -- ESC
                SendNUIMessage({ action = 'escape' })
            end
            Wait(0)
        end
        escWatcherActive = false
    end)
end

local function CloseUI()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    Tablet.Close()
    DebugPrint('UI lukket.')
end

RegisterNetEvent('mm-adminpakke:client:openUI', function(data)
    if isOpen then return end
    isOpen = true

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        items = data.items,
        players = data.players,
        imageBasePath = data.imageBasePath,
        blacklist = data.blacklist,
        categories = data.categories,
        uncategorized = data.uncategorized,
        weaponsCategory = data.weaponsCategory,
        maxItemAmount = data.maxItemAmount,
        itemsPerPage = data.itemsPerPage,
        theme = data.theme,
        debug = data.debug,
        missingImageManagerEnabled = data.missingImageManagerEnabled,
    })

    Tablet.Open()
    StartEscWatcher()
    DebugPrint('UI åbnet (%d items, %d spillere).', #(data.items or {}), #(data.players or {}))
end)

RegisterNetEvent('mm-adminpakke:client:playersUpdate', function(players)
    SendNUIMessage({ action = 'playersUpdate', players = players })
end)

RegisterNetEvent('mm-adminpakke:client:basketSent', function(success, errorMsg)
    SendNUIMessage({ action = 'basketSent', success = success, error = errorMsg })
end)

-- ------------------------------------------------------------------
--  KOMMANDO / KEYBIND
-- ------------------------------------------------------------------

RegisterCommand(Config.OpenCommand, function()
    TriggerServerEvent('mm-adminpakke:server:requestOpen')
end, false)

if Config.OpenKey then
    RegisterKeyMapping(Config.OpenCommand, 'Åbn mm-adminpakke', 'keyboard', Config.OpenKey)
end

-- ------------------------------------------------------------------
--  NUI CALLBACKS
-- ------------------------------------------------------------------

-- Bruges både til et almindeligt luk-klik OG til at afslutte NUI-siden
-- af en 'forceClose' (død/køretøj/logout - se client/tablet.lua's
-- ForceCloseEverything, som sender 'forceClose' til NUI'en, der selv
-- kalder denne callback som reaktion).
RegisterNUICallback('close', function(_, cb)
    CloseUI()
    cb({ ok = true })
end)

RegisterNUICallback('giveBasket', function(data, cb)
    if not data or not data.targetId or not data.basket then
        cb({ ok = false, error = 'Manglende data' })
        return
    end
    TriggerServerEvent('mm-adminpakke:server:giveBasket', data.targetId, data.basket)
    cb({ ok = true })
end)

RegisterNUICallback('refreshPlayers', function(_, cb)
    TriggerServerEvent('mm-adminpakke:server:refreshPlayers')
    cb({ ok = true })
end)

RegisterNUICallback('getPlayerProfile', function(data, cb)
    if not data or not data.targetId then
        cb(nil)
        return
    end
    local profile = lib.callback.await('mm-adminpakke:server:getPlayerProfile', false, data.targetId)
    cb(profile)
end)
