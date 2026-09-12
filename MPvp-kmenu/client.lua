-- ============================================================
--  MPvp-kmenu | client.lua
--  Ren NUI. Ingen ox_lib-menu, ingen inputDialog. K toggler NUI'en,
--  ESC lukker den (håndteret NUI-side, se web/app.js).
--
--  PERFORMANCE: ingen loops overhovedet. Åbn/luk sker udelukkende via
--  RegisterKeyMapping + NUI-callbacks — 0.00ms når menuen er lukket,
--  og selv når den er åben laver Lua intet arbejde (NUI'en tegner alt).
-- ============================================================

local menuOpen = false

-- Statisk config-data sendes kun i det øjeblik menuen faktisk åbnes —
-- ikke løbende, og aldrig i et loop.
local function BuildPayload()
    return {
        categories    = Config.Categories,
        weapons       = Config.Weapons,
        imagePath     = Config.InventoryImagePath,
        maxItemAmount = Config.MaxItemAmount,
    }
end

local function OpenMenu()
    if menuOpen then return end
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', payload = BuildPayload() })
end

local function CloseMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function ToggleMenu()
    if menuOpen then
        CloseMenu()
    else
        OpenMenu()
    end
end

-- RegisterKeyMapping: ingen permanent input-polling-loop. FiveM kalder
-- kun kommandoen når tasten rent faktisk trykkes, og spilleren kan selv
-- rebinde den via F8 > Settings > Key Bindings > FiveM.
RegisterCommand('mpvp_toggleweaponmenu', function()
    ToggleMenu()
end, false)

RegisterKeyMapping('mpvp_toggleweaponmenu', 'Åbn/luk våbenmenu (MPvp)', 'keyboard', Config.Key)

RegisterNUICallback('close', function(_, cb)
    CloseMenu()
    cb({})
end)

RegisterNUICallback('giveWeapon', function(data, cb)
    if data and data.key then
        TriggerServerEvent('mpvp_kmenu:give', 'weapon', data.key)
    end
    cb({})
end)

RegisterNUICallback('giveItem', function(data, cb)
    if data and data.key then
        TriggerServerEvent('mpvp_kmenu:give', 'item', data.key, data.amount)
    end
    cb({})
end)

-- Serveren svarer altid tilbage — succes eller fejl — så NUI'en kan
-- vise en toast. Aldrig noget der bare "håber" det virkede.
RegisterNetEvent('mpvp_kmenu:result', function(result)
    SendNUIMessage({ action = 'result', result = result })
end)

-- ─── CLEANUP ─────────────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if menuOpen then
        SetNuiFocus(false, false)
        menuOpen = false
    end
end)
