-- ============================================================
--  Masitz-AgriHub | client/main.lua
--  AgriHub-computeren (ox_target, ikke en distance-loop), NUI
--  åbn/luk, og landmand-NPC'erne (spawn + ox_target).
--
--  SIKKERHED: dette script har INGEN mening om hvorvidt spilleren har
--  adgang, er admin, eller kan betale for noget. Det sender KUN
--  ønsker til serveren og viser hvad serveren svarer. Alle beslutninger
--  tages i server/*.lua.
-- ============================================================

AH = AH or {}
AH.NuiOpen = false
AH.LoggedIn = false
AH.Role = nil

-- ─── NUI ÅBN / LUK ───────────────────────────────────────────────
function AH.OpenHub(focusTab)
    if AH.NuiOpen then return end
    AH.NuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', focusTab = focusTab })
end

function AH.CloseHub()
    if not AH.NuiOpen then return end
    AH.NuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb)
    AH.CloseHub()
    cb('ok')
end)

RegisterNetEvent('masitz_agrihub:forceLogout', function()
    AH.LoggedIn = false
    AH.Role = nil
    AH.CloseHub()
    lib.notify({ title = 'AgriHub', description = 'Din session blev afsluttet.', type = 'error' })
end)

-- ─── AGRIHUB-COMPUTEREN (§ event-drevet ox_target, ikke en loop) ──
CreateThread(function()
    local cfg = Config.Agri.Computer
    exports.ox_target:addBoxZone({
        coords = cfg.coords,
        size = vec3(0.6, 0.6, 1.2),
        rotation = 0.0,
        debug = Config.Agri.Debug,
        options = {
            {
                name = 'masitz_agrihub_computer',
                icon = cfg.icon,
                label = cfg.label,
                distance = cfg.distance,
                onSelect = function()
                    AH.OpenHub()
                end,
            },
        },
    })
end)

-- ─── LANDMÆND (§ ox_target, ingen distance-polling-loop) ─────────
-- Hver NPC spawnes én gang og får en ox_target-entity-zone. Peger
-- udelukkende videre til NUI'en (Opgaver/Udlejning) med farmerId sat,
-- så listen kan filtreres — al reel logik/pris/adgang afgøres server-side.
local function SpawnFarmer(farmer)
    local model = farmer.pedModel

    -- lib.requestModel FEJLER med error() (ikke et falsy return) hvis
    -- modellen er ugyldig — pcall her sikrer at ÉN forkert pedModel i
    -- config.lua ikke stopper resten af landmændene fra at spawne.
    local ok, err = pcall(lib.requestModel, model, 10000)
    if not ok then
        print(('[Masitz-AgriHub] Kunne ikke loade landmand-model for %s: %s'):format(farmer.id, tostring(err)))
        return
    end

    local ped = CreatePed(4, model, farmer.coords.x, farmer.coords.y, farmer.coords.z - 1.0, farmer.heading, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedDiesInWater(ped, false)
    SetPedCanRagdoll(ped, false)
    TaskSetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    SetModelAsNoLongerNeeded(model)

    local hasTasks = #farmer.tasks > 0
    local hasMachines = #farmer.machines > 0

    local options = {}
    if hasTasks then
        options[#options + 1] = {
            name = 'masitz_agrihub_farmer_tasks_' .. farmer.id,
            icon = 'fa-solid fa-clipboard-list',
            label = ('Se opgaver fra %s'):format(farmer.name),
            onSelect = function()
                AH.OpenHub({ tab = 'tasks', farmerId = farmer.id })
            end,
        }
    end
    if hasMachines then
        options[#options + 1] = {
            name = 'masitz_agrihub_farmer_rentals_' .. farmer.id,
            icon = 'fa-solid fa-tractor',
            label = ('Lej maskine hos %s'):format(farmer.name),
            onSelect = function()
                AH.OpenHub({ tab = 'rentals', farmerId = farmer.id })
            end,
        }
    end
    options[#options + 1] = {
        name = 'masitz_agrihub_farmer_info_' .. farmer.id,
        icon = 'fa-solid fa-user',
        label = ('Snak med %s'):format(farmer.name),
        onSelect = function()
            lib.alertDialog({
                header = farmer.name,
                content = ('%s kan levere til: %s\nMaskiner tilgængelige: %s'):format(
                    farmer.name,
                    #farmer.tasks > 0 and table.concat(farmer.tasks, ', ') or 'ingen aktive opgavetyper lige nu',
                    #farmer.machines > 0 and table.concat(farmer.machines, ', ') or 'ingen'
                ),
                centered = true,
            })
        end,
    }

    exports.ox_target:addLocalEntity(ped, options)
end

CreateThread(function()
    for _, farmer in ipairs(Config.Agri.Farmers) do
        SpawnFarmer(farmer)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if AH.NuiOpen then SetNuiFocus(false, false) end
end)
