-- ============================================================
--  Masitz-garage | client/cl_garage.lua
--  Kerne: zoner, markers, blips, spawn/store/dv, bil-/båd-/impound-
--  menuer. Uændret funktionalitet ift. MM-garage/kc_garage — kun
--  omdøbt til masitz_garage:*-events og flyttet til MGC.*-hjælpere.
--  Nye menu-punkter (rename/keys/sale/transfer) ligger i cl_menus.lua.
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

-- ─── LOKALE STATE VARIABLES ───────────────────────────────────
local nearZones      = {}     -- { [key] = { type='garage'|'impound', data={...} } }
local shownTextUI    = false
local currentTextKey = nil
local spawnLock      = {}     -- { [plate] = true } — forhindrer double-spawn
local storeLock      = false  -- Forhindrer double-store

-- ─── SPAWN VEHICLE ────────────────────────────────────────────
RegisterNetEvent('masitz_garage:spawnVehicleClient', function(payload)
    if type(payload) ~= 'table' or not payload.props then
        lib.notify({ type='error', description='Ugyldigt køretøjsdata.' })
        return
    end

    local props     = payload.props
    local coords    = payload.spawnCoords
    local model     = props.model
    local modelHash = type(model) == 'number' and model or joaat(model)
    local plate     = MGC.NormPlate(props.plate)

    if not model or not coords then
        lib.notify({ type='error', description='Manglende model eller spawn-koordinater.' })
        return
    end

    if spawnLock[plate] then
        lib.notify({ type='error', description='Køretøjet spawnes allerede.' })
        return
    end
    spawnLock[plate] = true

    if IsAnyVehicleNearPoint(coords.x, coords.y, coords.z, Config.SpawnClearRadius) then
        lib.notify({ type='error', description='Spawn-området er blokeret. Prøv igen om lidt.' })
        spawnLock[plate] = nil
        return
    end

    if not lib.requestModel(modelHash, Config.SpawnWaitTimeout) then
        lib.notify({ type='error', description='Kunne ikke loade køretøjsmodel.' })
        spawnLock[plate] = nil
        return
    end

    local veh = CreateVehicle(modelHash, coords.x, coords.y, coords.z, coords.w, true, true)

    local waited = 0
    while not DoesEntityExist(veh) and waited < Config.SpawnWaitTimeout do
        Wait(100)
        waited = waited + 100
    end

    if not DoesEntityExist(veh) then
        lib.notify({ type='error', description='Fejl ved oprettelse af køretøj.' })
        spawnLock[plate] = nil
        SetModelAsNoLongerNeeded(modelHash)
        return
    end

    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    SetVehRadioStation(veh, 'OFF')
    SetVehicleNeedsToBeHotwired(veh, false)
    MGC.SetVehicleProps(veh, props)
    TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    SetModelAsNoLongerNeeded(modelHash)
    spawnLock[plate] = nil

    lib.notify({
        type        = 'success',
        description = ('~w~%s~s~ trukket ud.'):format(MGC.GetVehicleLabel(model))
    })

    MGC.Log(('SPAWN CLIENT: %s spawnet'):format(plate))
end)

-- ─── DV VEHICLE ───────────────────────────────────────────────
RegisterNetEvent('masitz_garage:dvVehicle', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not veh or veh == 0 then return end

    NetworkRequestControlOfEntity(veh)
    local t = 0
    while not NetworkHasControlOfEntity(veh) and t < 50 do
        Wait(100); t = t + 1
    end

    if DoesEntityExist(veh) then
        SetEntityAsMissionEntity(veh, true, true)
        DeleteVehicle(veh)
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  GARAGE MENU (biler)
-- ═══════════════════════════════════════════════════════════

local function OpenVehicleActions(garageKey, v, label)
    local garage   = Config.Garages[garageKey]
    local plate    = v.plate
    local gpsLabel = garage and garage.label or garageKey

    local options = {
        {
            title       = '🔑 Tag bilen ud',
            description = 'Spawn køretøjet ved garagens udgang',
            icon        = 'key',
            onSelect    = function()
                local result = lib.callback.await('masitz_garage:spawnVehicle', false, plate, garageKey)
                if not result then
                    lib.notify({ type='error', description='Bilen kunne ikke trækkes ud.' })
                    return
                end
                TriggerEvent('masitz_garage:spawnVehicleClient', result)
            end
        },
        {
            title       = '🗺 Sæt GPS hertil',
            description = ('GPS til %s'):format(gpsLabel),
            icon        = 'location-dot',
            onSelect    = function()
                if garage then
                    SetNewWaypoint(garage.access.x, garage.access.y)
                    lib.notify({ type='inform', description='GPS sat til ' .. gpsLabel })
                end
            end
        },
        {
            title       = '✏️ Skift bilnavn',
            description = 'Giv køretøjet et personligt navn',
            icon        = 'pen',
            onSelect    = function() MGC.OpenRenameDialog(plate, v.vehicleName, function() OpenGarageMenu(garageKey) end) end
        },
        {
            title       = '🔑 Giv nøgler',
            description = 'Giv en anden spiller nøgler til denne bil',
            icon        = 'people-arrows',
            onSelect    = function() MGC.OpenGiveKeysDialog(plate) end
        },
        {
            title       = '💰 Sælg bil',
            description = 'Sælg køretøjet til en anden spiller',
            icon        = 'hand-holding-dollar',
            onSelect    = function() MGC.OpenSellDialog(plate, v, label) end
        },
        {
            title       = '🏢 Flyt bil',
            description = 'Flyt køretøjet til en anden garage',
            icon        = 'truck-ramp-box',
            onSelect    = function() MGC.OpenTransferOutMenu(plate, garageKey, function() OpenGarageMenu(garageKey) end) end
        },
        {
            title       = '📋 Kopiér nummerplade',
            description = plate,
            icon        = 'clipboard',
            onSelect    = function()
                lib.setClipboard(plate)
                lib.notify({ type='success', description='Nummerplade kopieret: ' .. plate })
            end
        },
        {
            title       = 'ℹ️ Køretøjsinfo',
            description = ('Model: %s | Motor: %d%% | Karosseri: %d%% | Fuel: %d%%'):format(
                v.model or '?',
                math.floor(((v.engineHealth or 1000)/1000)*100),
                math.floor(((v.bodyHealth   or 1000)/1000)*100),
                math.floor(v.fuel or 100)
            ),
            icon        = 'circle-info',
            readOnly    = true
        },
    }

    lib.registerContext({
        id    = 'garage_actions_' .. plate,
        title = '🚗 ' .. label:upper() .. ' · ' .. plate,
        menu  = 'garage_main_' .. garageKey,
        options = options,
    })
    lib.showContext('garage_actions_' .. plate)
end

function OpenGarageMenu(garageKey)
    local garage = Config.Garages[garageKey]
    if not garage then return end

    local vehicles = lib.callback.await('masitz_garage:getVehicles', false, garageKey)
    if not vehicles or #vehicles == 0 then
        MGC.OpenEmptyGarageMenu(garageKey)
        return
    end

    local options = {}
    for _, v in ipairs(vehicles) do
        local label = MGC.GetVehicleLabel(v.model)
        local displayName = MGC.GetDisplayName(v.vehicleName, v.model)
        local fuelPct = math.floor((v.fuel or 100) + 0.5)
        local cond = MGC.GetConditionInfo(v.engineHealth, v.bodyHealth)

        table.insert(options, {
            title = displayName:upper(),
            description = (
                '🚘 Nummerplade: %s\n' ..
                '⛽ Brændstof: %d%%\n' ..
                '🔧 Motor: %d%%\n' ..
                '🚗 Karosseri: %d%%\n' ..
                '📍 Stand: %s'
            ):format(v.plate, fuelPct, cond.engPct, cond.bodyPct, cond.text),
            icon        = 'car',
            progress    = cond.avg,
            colorScheme = cond.colorScheme,
            onSelect    = function() OpenVehicleActions(garageKey, v, label) end
        })
    end

    lib.registerContext({
        id      = 'garage_main_' .. garageKey,
        title   = '🏢 ' .. (garage.label or garageKey),
        options = options,
    })
    lib.showContext('garage_main_' .. garageKey)
end

-- ═══════════════════════════════════════════════════════════
--  BOAT GARAGE MENU
-- ═══════════════════════════════════════════════════════════

-- ── Boat Vehicle Actions Submenu ──
local function OpenBoatVehicleActions(boatKey, v, label)
    local marina   = Config.Boat[boatKey]
    local plate    = v.plate
    local gpsLabel = marina and marina.label or boatKey

    lib.registerContext({
        id    = 'boat_actions_' .. plate,
        title = '⛵ ' .. label:upper() .. ' · ' .. plate,
        menu  = 'boat_main_' .. boatKey,
        options = {
            {
                title       = '🔑 Tag båden ud',
                description = 'Spawn båden ved marinens udgang',
                icon        = 'key',
                onSelect    = function()
                    local result = lib.callback.await('masitz_garage:spawnBoat', false, plate, boatKey)
                    if not result then
                        lib.notify({ type='error', description='Båden kunne ikke trækkes ud.' })
                        return
                    end
                    TriggerEvent('masitz_garage:spawnVehicleClient', result)
                end
            },
            {
                title       = '🗺 Sæt GPS hertil',
                description = ('GPS til %s'):format(gpsLabel),
                icon        = 'location-dot',
                onSelect    = function()
                    if marina then
                        SetNewWaypoint(marina.access.x, marina.access.y)
                        lib.notify({ type='inform', description='GPS sat til ' .. gpsLabel })
                    end
                end
            },
            {
                title       = '✏️ Skift bådnavn',
                description = 'Giv fartøjet et personligt navn',
                icon        = 'pen',
                onSelect    = function() MGC.OpenRenameDialog(plate, v.vehicleName, function() OpenBoatMenu(boatKey) end) end
            },
            {
                title       = '🔑 Giv nøgler',
                description = 'Giv en anden spiller nøgler til denne båd',
                icon        = 'people-arrows',
                onSelect    = function() MGC.OpenGiveKeysDialog(plate) end
            },
            {
                title       = '💰 Sælg båd',
                description = 'Sælg fartøjet til en anden spiller',
                icon        = 'hand-holding-dollar',
                onSelect    = function() MGC.OpenSellDialog(plate, v, label) end
            },
            {
                title       = '📋 Kopiér nummerplade',
                description = plate,
                icon        = 'clipboard',
                onSelect    = function()
                    lib.setClipboard(plate)
                    lib.notify({ type='success', description='Nummerplade kopieret: ' .. plate })
                end
            },
            {
                title       = 'ℹ️ Fartøjsinfo',
                description = ('Model: %s | Motor: %d%% | Karosseri: %d%% | Fuel: %d%%'):format(
                    v.model or '?',
                    math.floor(((v.engineHealth or 1000)/1000)*100),
                    math.floor(((v.bodyHealth   or 1000)/1000)*100),
                    math.floor(v.fuel or 100)
                ),
                icon        = 'circle-info',
                readOnly    = true
            },
        }
    })
    lib.showContext('boat_actions_' .. plate)
end

-- ── Main Boat Menu ──
function OpenBoatMenu(boatKey)
    local marina = Config.Boat[boatKey]
    if not marina then return end

    local vehicles = lib.callback.await('masitz_garage:getBoats', false, boatKey)
    if not vehicles or #vehicles == 0 then
        lib.notify({ type='error', description='Ingen både parkeret her.' })
        return
    end

    local options = {}
    for _, v in ipairs(vehicles) do
        local label = MGC.GetVehicleLabel(v.model)
        local displayName = MGC.GetDisplayName(v.vehicleName, v.model)
        local fuelPct = math.floor((v.fuel or 100) + 0.5)
        local cond = MGC.GetConditionInfo(v.engineHealth, v.bodyHealth)

        table.insert(options, {
            title = displayName:upper(),
            description = (
                '⛵ Nummerplade: %s\n' ..
                '⛽ Brændstof: %d%%\n' ..
                '🔧 Motor: %d%%\n' ..
                '🚢 Karosseri: %d%%\n' ..
                '📍 Stand: %s'
            ):format(v.plate, fuelPct, cond.engPct, cond.bodyPct, cond.text),
            icon        = 'anchor',
            progress    = cond.avg,
            colorScheme = cond.colorScheme,
            onSelect    = function() OpenBoatVehicleActions(boatKey, v, label) end
        })
    end

    lib.registerContext({
        id      = 'boat_main_' .. boatKey,
        title   = '⚓ ' .. (marina.label or boatKey),
        options = options,
    })
    lib.showContext('boat_main_' .. boatKey)
end

-- ═══════════════════════════════════════════════════════════
--  IMPOUND MENU
-- ═══════════════════════════════════════════════════════════

function OpenImpoundMenu(impoundKey)
    local impound = Config.Impounds[impoundKey]
    if not impound then return end

    local vehicles = lib.callback.await('masitz_garage:getImpounded', false, impoundKey)
    if not vehicles or #vehicles == 0 then
        lib.notify({ type='error', description='Ingen biler på dette impound.' })
        return
    end

    local options = {}
    for _, v in ipairs(vehicles) do
        local label = MGC.GetDisplayName(v.vehicleName, v.model)
        table.insert(options, {
            title       = ('~w~%s~s~'):format(label:upper()),
            description = (
                '~y~#~s~ %s\n' ..
                '⚠️ Årsag: ~r~%s~s~\n' ..
                '💰 Gebyr: ~y~%s~s~'
            ):format(v.plate, v.reason, MGC.FormatMoney(v.fee)),
            icon        = 'car-burst',
            onSelect    = function()
                lib.registerContext({
                    id    = 'impound_action_' .. v.plate,
                    title = '⚠️ ' .. label:upper() .. ' · Impound',
                    menu  = 'impound_main_' .. impoundKey,
                    options = {
                        {
                            title       = ('💸 Betal %s og hent bil'):format(MGC.FormatMoney(v.fee)),
                            description = 'Bilen returneres til din last_garage',
                            icon        = 'money-bill',
                            onSelect    = function()
                                local result = lib.callback.await('masitz_garage:releaseImpound', false, v.plate, impoundKey)
                                if result and result.success then
                                    lib.notify({
                                        type        = 'success',
                                        description = ('Bil hentet! Betalte %s.'):format(MGC.FormatMoney(result.fee))
                                    })
                                else
                                    lib.notify({
                                        type        = 'error',
                                        description = (result and result.msg) or 'Fejl ved hentning.'
                                    })
                                end
                            end
                        },
                        {
                            title    = '❌ Afbryd',
                            icon     = 'xmark',
                            onSelect = function() lib.showContext('impound_main_' .. impoundKey) end
                        }
                    }
                })
                lib.showContext('impound_action_' .. v.plate)
            end
        })
    end

    lib.registerContext({
        id      = 'impound_main_' .. impoundKey,
        title   = '⚠️ ' .. (impound.label or impoundKey),
        options = options,
    })
    lib.showContext('impound_main_' .. impoundKey)
end

-- ═══════════════════════════════════════════════════════════
--  STORE VEHICLE (bil)
-- ═══════════════════════════════════════════════════════════

local function TryStoreVehicle(garageKey)
    if storeLock then
        lib.notify({ type='error', description='Allerede ved at parkere.' })
        return
    end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh == 0 then
        lib.notify({ type='error', description='Du skal sidde i et køretøj.' })
        return
    end

    local props = MGC.GetVehicleProps(veh)
    if not props then
        lib.notify({ type='error', description='Kunne ikke læse køretøjsdata.' })
        return
    end

    local plate = MGC.NormPlate(props.plate)
    if not plate then
        lib.notify({ type='error', description='Ugyldigt registreringsskilt.' })
        return
    end

    NetworkRegisterEntityAsNetworked(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)

    storeLock = true
    local finished = lib.progressBar({
        duration = Config.StoreDuration,
        label    = 'Parkerer køretøj...',
        canCancel= false,
        disable  = { move=true, car=true, combat=true },
    })
    storeLock = false

    if finished then
        TriggerServerEvent('masitz_garage:storeVehicle', plate, garageKey, props, netId)
    end
end

-- ═══════════════════════════════════════════════════════════
--  STORE BOAT
-- ═══════════════════════════════════════════════════════════

local function TryStoreBoat(boatKey)
    if storeLock then
        lib.notify({ type='error', description='Allerede ved at parkere.' })
        return
    end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh == 0 then
        lib.notify({ type='error', description='Du skal sidde i en båd.' })
        return
    end

    -- Kun vehicle class 14 (boats)
    if GetVehicleClass(veh) ~= 14 then
        lib.notify({ type='error', description='Kun både kan parkeres her.' })
        return
    end

    local props = MGC.GetVehicleProps(veh)
    if not props then
        lib.notify({ type='error', description='Kunne ikke læse fartøjsdata.' })
        return
    end

    local plate = MGC.NormPlate(props.plate)
    if not plate then
        lib.notify({ type='error', description='Ugyldigt registreringsskilt.' })
        return
    end

    NetworkRegisterEntityAsNetworked(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)

    storeLock = true
    local finished = lib.progressBar({
        duration = Config.StoreDuration,
        label    = 'Fortøjer båd...',
        canCancel= false,
        disable  = { move=true, car=true, combat=true },
    })
    storeLock = false

    if finished then
        TriggerServerEvent('masitz_garage:storeBoat', plate, boatKey, props, netId)
    end
end

-- ═══════════════════════════════════════════════════════════
--  HOVED LOOP — Zoner, Markers, Interaktion
-- ═══════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        local sleep    = 1000
        local ped      = PlayerPedId()
        local coords   = GetEntityCoords(ped)
        local bestZone = nil
        local bestDist = math.huge

        -- ── Scan garager (biler) ──────────────────────────
        for key, v in pairs(Config.Garages) do
            local dAccess = #(coords - v.access)
            local dStore  = #(coords - v.store)

            if dAccess < Config.DrawDistance or dStore < Config.DrawDistance then
                sleep = 0

                DrawMarker(Config.AccessMarker.type,
                    v.access.x, v.access.y, v.access.z + Config.AccessMarker.height,
                    0,0,0,0,0,0,
                    Config.AccessMarker.size.x, Config.AccessMarker.size.y, Config.AccessMarker.size.z,
                    Config.AccessMarker.r, Config.AccessMarker.g, Config.AccessMarker.b, Config.AccessMarker.a,
                    false, true, 2)

                DrawMarker(Config.StoreMarker.type,
                    v.store.x, v.store.y, v.store.z + Config.StoreMarker.height,
                    0,0,0,0,0,0,
                    Config.StoreMarker.size.x, Config.StoreMarker.size.y, Config.StoreMarker.size.z,
                    Config.StoreMarker.r, Config.StoreMarker.g, Config.StoreMarker.b, Config.StoreMarker.a,
                    false, true, 2)

                if dAccess < Config.AccessDistance and dAccess < bestDist then
                    bestDist = dAccess
                    bestZone = { type='garage_access', key=key, text=Config.AccessMarker.text }
                end

                if dStore < Config.StoreDistance and dStore < bestDist then
                    bestDist = dStore
                    bestZone = { type='garage_store', key=key, text=Config.StoreMarker.text }
                end
            end
        end

        -- ── Scan impounds ─────────────────────────────────
        for key, v in pairs(Config.Impounds) do
            local dAccess = #(coords - v.access)

            if dAccess < Config.DrawDistance then
                sleep = 0

                DrawMarker(Config.ImpoundMarker.type,
                    v.access.x, v.access.y, v.access.z + Config.ImpoundMarker.height,
                    0,0,0,0,0,0,
                    Config.ImpoundMarker.size.x, Config.ImpoundMarker.size.y, Config.ImpoundMarker.size.z,
                    Config.ImpoundMarker.r, Config.ImpoundMarker.g, Config.ImpoundMarker.b, Config.ImpoundMarker.a,
                    false, true, 2)

                if dAccess < Config.AccessDistance and dAccess < bestDist then
                    bestDist = dAccess
                    bestZone = { type='impound_access', key=key, text=Config.ImpoundMarker.text }
                end
            end
        end

        -- ── Scan boat garager ─────────────────────────────
        for key, v in pairs(Config.Boat) do
            local dAccess = #(coords - v.access)
            local dStore  = #(coords - v.store)

            if dAccess < Config.DrawDistance or dStore < Config.DrawDistance then
                sleep = 0

                DrawMarker(Config.BoatAccessMarker.type,
                    v.access.x, v.access.y, v.access.z + Config.BoatAccessMarker.height,
                    0,0,0,0,0,0,
                    Config.BoatAccessMarker.size.x, Config.BoatAccessMarker.size.y, Config.BoatAccessMarker.size.z,
                    Config.BoatAccessMarker.r, Config.BoatAccessMarker.g, Config.BoatAccessMarker.b, Config.BoatAccessMarker.a,
                    false, true, 2)

                DrawMarker(Config.BoatStoreMarker.type,
                    v.store.x, v.store.y, v.store.z + Config.BoatStoreMarker.height,
                    0,0,0,0,0,0,
                    Config.BoatStoreMarker.size.x, Config.BoatStoreMarker.size.y, Config.BoatStoreMarker.size.z,
                    Config.BoatStoreMarker.r, Config.BoatStoreMarker.g, Config.BoatStoreMarker.b, Config.BoatStoreMarker.a,
                    false, true, 2)

                if dAccess < Config.AccessDistance and dAccess < bestDist then
                    bestDist = dAccess
                    bestZone = { type='boat_access', key=key, text=Config.BoatAccessMarker.text }
                end

                if dStore < Config.StoreDistance and dStore < bestDist then
                    bestDist = dStore
                    bestZone = { type='boat_store', key=key, text=Config.BoatStoreMarker.text }
                end
            end
        end

        -- ── TextUI håndtering ─────────────────────────────
        if bestZone then
            local zoneId = bestZone.type .. '_' .. bestZone.key
            if not shownTextUI or currentTextKey ~= zoneId then
                if shownTextUI then lib.hideTextUI() end
                lib.showTextUI(bestZone.text)
                shownTextUI    = true
                currentTextKey = zoneId
            end

            if IsControlJustPressed(0, 38) then
                if bestZone.type == 'garage_access' then
                    OpenGarageMenu(bestZone.key)
                elseif bestZone.type == 'garage_store' then
                    TryStoreVehicle(bestZone.key)
                elseif bestZone.type == 'impound_access' then
                    OpenImpoundMenu(bestZone.key)
                elseif bestZone.type == 'boat_access' then
                    OpenBoatMenu(bestZone.key)
                elseif bestZone.type == 'boat_store' then
                    TryStoreBoat(bestZone.key)
                end
            end
        else
            if shownTextUI then
                lib.hideTextUI()
                shownTextUI    = false
                currentTextKey = nil
            end
        end

        Wait(sleep)
    end
end)

-- ═══════════════════════════════════════════════════════════
--  BLIPS
-- ═══════════════════════════════════════════════════════════

CreateThread(function()
    for key, v in pairs(Config.Garages) do
        if v.blip then
            local cfg  = Config.GarageBlip[v.type] or Config.GarageBlip.car
            local blip = AddBlipForCoord(v.access.x, v.access.y, v.access.z)
            SetBlipSprite(blip,  cfg.sprite)
            SetBlipScale(blip,   cfg.scale)
            SetBlipColour(blip,  cfg.colour)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(v.label or key)
            EndTextCommandSetBlipName(blip)
        end
    end

    for key, v in pairs(Config.Impounds) do
        if v.blip then
            local cfg  = Config.ImpoundBlip
            local blip = AddBlipForCoord(v.access.x, v.access.y, v.access.z)
            SetBlipSprite(blip,  cfg.sprite)
            SetBlipScale(blip,   cfg.scale)
            SetBlipColour(blip,  cfg.colour)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(v.label or key)
            EndTextCommandSetBlipName(blip)
        end
    end

    -- ── Boat blips ────────────────────────────────────────
    for key, v in pairs(Config.Boat) do
        if v.blip then
            local cfg  = Config.BoatBlip
            local blip = AddBlipForCoord(v.access.x, v.access.y, v.access.z)
            SetBlipSprite(blip,  cfg.sprite)
            SetBlipScale(blip,   cfg.scale)
            SetBlipColour(blip,  cfg.colour)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(v.label or key)
            EndTextCommandSetBlipName(blip)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
--  CLEANUP
-- ═══════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if shownTextUI then lib.hideTextUI() end
end)
