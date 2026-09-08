-- ============================================================
-- MM-PolitiJob – client/functions/garage.lua  REWORK
-- Garage menu + heli menu + spawn + park
--
-- REWORK: spawn/park går nu via server-callbacks
-- (mm_police:cb:requestSpawnVehicle / mm_police:cb:parkVehicle).
-- Kun køretøjer denne klient selv har fået godkendt og spawnet
-- (sporet i spawnedByMe) kan parkeres — en civil bil, eller et
-- vilkårligt andet køretøj, kan derfor aldrig "parkeres" (slettes)
-- via politi-garagen.
-- ============================================================

local spawnedByMe = {}   -- [netId] = true, køretøjer DENNE klient har hentet ud

-- ── EKSPORTÉR FUNKTIONER ─────────────────────────────────────
local function SpawnVehicle(model, spawnType)
    local ok, reason = lib.callback.await('mm_police:cb:requestSpawnVehicle', false, model, spawnType)
    if not ok then
        lib.notify({
            title       = 'Garage',
            description = reason or 'Du må ikke hente dette køretøj.',
            type        = 'error',
            position    = 'center-right',
        })
        return
    end

    local spawnCfg = spawnType == 'heli' and Config.HeliSpawn or Config.GarageSpawn

    lib.requestModel(model, function()
        if not HasModelLoaded(GetHashKey(model)) then
            lib.notify({ title = 'Fejl', description = 'Modellen kunne ikke indlæses.', type = 'error', position = 'center-right' })
            return
        end

        local veh = CreateVehicle(
            GetHashKey(model),
            spawnCfg.coords.x, spawnCfg.coords.y, spawnCfg.coords.z,
            spawnCfg.heading, true, false
        )

        SetPedIntoVehicle(cache.ped, veh, -1)
        SetVehicleHasBeenOwnedByPlayer(veh, true)
        SetVehicleFuelLevel(veh, 100.0)
        SetVehicleDirtLevel(veh, 0.0)
        SetVehicleEngineOn(veh, true, true, false)
        SetModelAsNoLongerNeeded(GetHashKey(model))

        local netId = VehToNet(veh)
        spawnedByMe[netId] = true
        TriggerServerEvent('mm_police:server:registerSpawnedVehicle', netId)

        lib.notify({ title = 'Garage', description = ('Du hentede: %s'):format(model), type = 'success', position = 'center-right' })

        if Config.Debug then
            print(('[MM-PolitiJob] Spawnede %s (netId=%d)'):format(model, netId))
        end
    end)
end

-- ── GARAGE MENU ──────────────────────────────────────────────
local function OpenGarageMenu()
    -- FIX: garage-adgang blev tidligere kun tjekket af kalderen
    -- (client/main.lua). Da funktionen er eksporteret, kunne den
    -- kaldes direkte og springe tjekket over. Tjek nu direkte her.
    if not MM.Framework.IsPolice() then
        lib.notify({ title = 'Adgang nægtet', description = 'Du er ikke ansat i politiet.', type = 'error', position = 'center-right' })
        return
    end

    local options = {}

    for category, vehicles in pairs(Config.Vehicles) do
        if category ~= 'Heli' then
            table.insert(options, {
                title       = '🚗 ' .. category,
                description = 'Vis ' .. category .. ' køretøjer',
                arrow       = true,
                menu        = 'mm_garage_sub_' .. category,
            })
        end
    end

    lib.registerContext({ id = 'mm_garage_main', title = '🚓 Politi Garage', options = options })

    for category, vehicles in pairs(Config.Vehicles) do
        if category ~= 'Heli' then
            local opts = {}
            for _, v in ipairs(vehicles) do
                opts[#opts + 1] = {
                    title    = v.label,
                    icon     = 'fa-solid fa-car',
                    onSelect = function()
                        SpawnVehicle(v.model, 'car')
                    end,
                }
            end
            lib.registerContext({
                id      = 'mm_garage_sub_' .. category,
                title   = '🚗 ' .. category,
                menu    = 'mm_garage_main',
                options = opts,
            })
        end
    end

    lib.showContext('mm_garage_main')
end

local function OpenHeliMenu()
    if not MM.Framework.IsPolice() then
        lib.notify({ title = 'Adgang nægtet', description = 'Du er ikke ansat i politiet.', type = 'error', position = 'center-right' })
        return
    end

    local options = {}
    for _, v in ipairs(Config.Vehicles.Heli) do
        options[#options + 1] = {
            title    = v.label,
            icon     = 'fa-solid fa-helicopter',
            onSelect = function()
                SpawnVehicle(v.model, 'heli')
            end,
        }
    end
    lib.registerContext({ id = 'mm_heli_menu', title = '🚁 Helikopter Garage', options = options })
    lib.showContext('mm_heli_menu')
end

-- ── PARKÉR ────────────────────────────────────────────────────
local function ParkVehicle()
    -- FIX: manglede tidligere HELT et jobtjek — enhver spiller kunne
    -- kalde dette (via garagens park-markør) og få deres køretøj
    -- slettet/"parkeret", uanset job eller om det var et politikøretøj.
    if not MM.Framework.IsPolice() then
        lib.notify({ title = 'Adgang nægtet', description = 'Du er ikke ansat i politiet.', type = 'error', position = 'center-right' })
        return
    end

    local ped = cache.ped
    local veh = GetVehiclePedIsIn(ped, false)

    if veh == 0 then
        lib.notify({ title = 'Garage', description = 'Du sidder ikke i et køretøj!', type = 'error', position = 'center-right' })
        return
    end
    if GetPedInVehicleSeat(veh, -1) ~= ped then
        lib.notify({ title = 'Garage', description = 'Du skal sidde på førersædet!', type = 'error', position = 'center-right' })
        return
    end

    local netId = VehToNet(veh)

    -- FIX: kun køretøjer der faktisk blev spawnet via garagen kan
    -- parkeres her — en civil bil (eller en anden spillers køretøj)
    -- kan aldrig "parkeres"/slettes i politi-garagen.
    if not spawnedByMe[netId] then
        lib.notify({ title = 'Garage', description = 'Dette køretøj kan ikke parkeres i politi-garagen.', type = 'error', position = 'center-right' })
        return
    end

    local ok = lib.callback.await('mm_police:cb:parkVehicle', false, netId)
    if not ok then
        lib.notify({ title = 'Garage', description = 'Køretøjet kunne ikke parkeres.', type = 'error', position = 'center-right' })
        return
    end

    spawnedByMe[netId] = nil
    DeleteVehicle(veh)
    lib.notify({ title = 'Garage', description = 'Køretøjet er parkeret.', type = 'success', position = 'center-right' })
end

-- ── EXPORTS ──────────────────────────────────────────────────
exports('OpenGarageMenu', OpenGarageMenu)
exports('OpenHeliMenu',   OpenHeliMenu)
exports('ParkVehicle',    ParkVehicle)
