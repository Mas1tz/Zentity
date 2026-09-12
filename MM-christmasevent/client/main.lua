-- ══════════════════════════════════════════════════════════
--  CLIENT — mm-christmas
-- ══════════════════════════════════════════════════════════

Shared.LoadLocale(Config.Locale)

-- ── STATE ────────────────────────────────────────────────
local PlayerData      = {}
local UIOpen           = false
local ActiveGiftProps  = {}   -- giftId -> { prop = entity, blip = blip }
local WorldGiftProps   = {}   -- locIndex -> entity
local SnowmanProps     = {}   -- locIndex -> entity
local SnowmanTakenUntil= {}   -- locIndex -> GetGameTimer() expiry (client-side UX hint only)
local TreeProps        = {}   -- index -> entity
local LastPos          = nil
local DrivingDistance  = 0
local RunningDistance  = 0
local DistanceBuffer   = 0
local LastSendTime     = 0

local RESOURCE = GetCurrentResourceName()

-- ── PROP GROUND HELPER ───────────────────────────────────
local function PlacePropOnGround(prop, x, y, z)
    SetEntityCoords(prop, x, y, z + 2.0, false, false, false, false)
    Wait(100)
    PlaceObjectOnGroundProperly(prop)
    Wait(50)

    local groundZ, groundFound = GetGroundZAndNormalFor_3dCoord(x, y, z + 5.0)
    if groundFound then
        SetEntityCoords(prop, x, y, groundZ, false, false, false, false)
    end
end

-- ── ANIMATION HELPER ─────────────────────────────────────
local function PlayAnim(dict, anim, duration)
    local ok = pcall(function() lib.requestAnimDict(dict) end)
    if not ok or not HasAnimDictLoaded(dict) then
        Wait(duration or 2000)
        return
    end
    TaskPlayAnim(cache.ped, dict, anim, 8.0, -8.0, duration or 2000, 1, 0, false, false, false)
    Wait(duration or 2000)
    ClearPedTasks(cache.ped)
end

-- ── NOTIFY ───────────────────────────────────────────────
local function Notify(title, ntype, duration, icon)
    lib.notify({ title = title, type = ntype or 'inform', duration = duration or 3000, icon = icon })
end

-- ── SYNC DATA FROM SERVER ────────────────────────────────
RegisterNetEvent('mm-christmas:client:syncData', function(data)
    PlayerData = data
    if UIOpen then
        SendNUIMessage({ action = 'syncData', data = PlayerData })
    end
end)

-- ── OPEN / CLOSE UI (centraliseret — brugt af event/command/keybind) ──
local function BuildHints()
    -- os.date findes ikke client-side i FiveM — brug GetCloudTimeAsInt()
    -- divideret med sekunder pr. dag for et deterministisk dagligt tal.
    local dayNumber = math.floor(GetCloudTimeAsInt() / 86400)
    math.randomseed(dayNumber)

    local treeIdx = math.random(1, #Config.Trees)
    local snowIdx = math.random(1, #Config.SnowmanLocations)

    local treeEntry = Config.Trees[treeIdx]
    local snowEntry = Config.SnowmanLocations[snowIdx]

    return {
        tree    = treeEntry.hint or 'Et sted i byen...',
        snowman = (type(snowEntry) == 'table' and snowEntry.hint) or 'Et sted i byen...',
    }
end

local function OpenUI()
    if not Shared.IsEventActive() then
        Notify(T('event_not_active'), 'error')
        return
    end
    if UIOpen then return end

    TriggerServerEvent('mm-christmas:server:openUI')
    TriggerServerEvent('mm-christmas:server:getProfileImage')

    UIOpen = true
    SetNuiFocus(true, true)

    SendNUIMessage({
        action       = 'injectConfig',
        shopItems    = Config.ShopItems,
        levelRewards = Config.LevelRewards,
        hints        = BuildHints(),
        ui           = Config.UI,
    })
    SendNUIMessage({ action = 'open', data = PlayerData })
end

local function CloseUI()
    if not UIOpen then return end
    UIOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNetEvent('mm-christmas:client:openUI', OpenUI)

RegisterCommand('christmas', OpenUI, false)

lib.addKeybind({
    name        = 'christmas_open',
    description = 'Åbn Christmas Event Menu',
    defaultKey  = 'F5',
    onPressed   = function()
        if UIOpen then CloseUI() else OpenUI() end
    end
})

-- ── NUI CALLBACKS ────────────────────────────────────────
-- Alle callbacks validerer input minimalt client-side (typen), men den
-- reelle validering sker altid server-side — clienten er ikke trusted.
-- Alle callbacks kalder ALTID cb() med det samme, så NUI aldrig hænger
-- i "loading forever" mens den venter på et serversvar der aldrig kommer
-- direkte tilbage som callback-response (svaret kommer i stedet som et
-- separat syncData/leaderboardData/profileImage event).
RegisterNUICallback('close', function(_, cb)
    CloseUI()
    cb('ok')
end)

RegisterNUICallback('getLeaderboard', function(_, cb)
    TriggerServerEvent('mm-christmas:server:getLeaderboard')
    cb('ok')
end)

RegisterNUICallback('shopBuy', function(data, cb)
    if type(data) == 'table' and type(data.id) == 'string' then
        TriggerServerEvent('mm-christmas:server:shopBuy', data.id)
    end
    cb('ok')
end)

RegisterNUICallback('openBox', function(_, cb)
    TriggerServerEvent('mm-christmas:server:openBox')
    cb('ok')
end)

-- Denne callback manglede helt i den oprindelige version — knappen i
-- UI'en kaldte 'claimLevelReward', men intet lyttede efter den, så
-- level-belønninger reelt aldrig kunne hentes fra UI'en.
RegisterNUICallback('claimLevelReward', function(data, cb)
    local level = type(data) == 'table' and tonumber(data.level) or nil
    if level then
        TriggerServerEvent('mm-christmas:server:claimLevelReward', level)
    end
    cb('ok')
end)

RegisterNUICallback('getProfileImage', function(_, cb)
    TriggerServerEvent('mm-christmas:server:getProfileImage')
    cb('ok')
end)

-- ── LEADERBOARD DATA ─────────────────────────────────────
RegisterNetEvent('mm-christmas:client:leaderboardData', function(data)
    SendNUIMessage({ action = 'leaderboardData', data = data })
end)

-- ── PROFILE AVATAR ───────────────────────────────────────
RegisterNetEvent('mm-christmas:client:profileImage', function(url)
    SendNUIMessage({ action = 'profileImage', url = url })
end)

-- ── JULETRÆER ────────────────────────────────────────────
local function SpawnTrees()
    for i, tree in ipairs(Config.Trees) do
        local model = GetHashKey(Config.TreeProp)
        lib.requestModel(model)
        local prop = CreateObject(model, tree.coords.x, tree.coords.y, tree.coords.z, false, false, false)
        SetEntityHeading(prop, tree.heading or 0.0)
        SetEntityCollision(prop, true, true)
        PlacePropOnGround(prop, tree.coords.x, tree.coords.y, tree.coords.z)
        FreezeEntityPosition(prop, true)
        TreeProps[i] = prop

        exports.ox_target:addLocalEntity(prop, {
            {
                name     = 'christmas_tree_' .. i,
                label    = T('tree_decorate'),
                icon     = 'fas fa-tree',
                distance = 2.0,
                onSelect = function()
                    if PlayerData.treesDone then
                        for _, v in ipairs(PlayerData.treesDone) do
                            if v == i then
                                Notify(T('tree_already_done'), 'error')
                                return
                            end
                        end
                    end
                    CreateThread(function()
                        PlayAnim(Config.Animations.decorTree.dict, Config.Animations.decorTree.anim, Config.Animations.decorTree.duration)
                        TriggerServerEvent('mm-christmas:server:decorateTree', i)
                    end)
                end
            }
        })
    end
end

RegisterNetEvent('mm-christmas:client:treeDecorated', function(treeIndex)
    local prop = TreeProps[treeIndex]
    if prop and DoesEntityExist(prop) then
        local coords = GetEntityCoords(prop)
        UseParticleFxAssetNextCall('core')
        StartParticleFxLoopedAtCoords('ent_anim_paparazzi_flash', coords.x, coords.y, coords.z + 1.5, 0, 0, 0, 0.5, false, false, false, false)
    end
end)

-- ── SNEMÆND ──────────────────────────────────────────────
local function SpawnSnowmanProp(locIndex, ttlMs)
    if SnowmanProps[locIndex] and DoesEntityExist(SnowmanProps[locIndex]) then return end

    local entry = Config.SnowmanLocations[locIndex]
    local loc   = type(entry) == 'table' and entry.coords or entry

    local model = GetHashKey(Config.SnowmanProp)
    lib.requestModel(model)
    local prop = CreateObject(model, loc.x, loc.y, loc.z, false, false, false)
    SetEntityCollision(prop, true, true)
    PlacePropOnGround(prop, loc.x, loc.y, loc.z)
    FreezeEntityPosition(prop, true)
    SnowmanProps[locIndex] = prop

    CreateThread(function()
        Wait(ttlMs or Config.SnowmanDespawnTime)
        if DoesEntityExist(prop) then DeleteObject(prop) end
        if SnowmanProps[locIndex] == prop then SnowmanProps[locIndex] = nil end
        SnowmanTakenUntil[locIndex] = nil
    end)
end

-- Server-broadcast: en snemand blev bygget (af en hvilken som helst
-- spiller) — spawn den lokale visuelle repræsentation for ALLE clients,
-- ikke kun den der byggede den.
RegisterNetEvent('mm-christmas:client:snowmanBuilt', function(locIndex, despawnMs)
    SnowmanTakenUntil[locIndex] = GetGameTimer() + (despawnMs or Config.SnowmanDespawnTime)
    SpawnSnowmanProp(locIndex, despawnMs)
end)

-- Server sender denne ved join, så en spiller der joiner midt i et
-- event straks ser allerede-aktive snemænd.
RegisterNetEvent('mm-christmas:client:activeSnowmen', function(list)
    for _, entry in ipairs(list or {}) do
        SnowmanTakenUntil[entry.index] = GetGameTimer() + entry.expiresIn
        SpawnSnowmanProp(entry.index, entry.expiresIn)
    end
end)

local function SpawnSnowmanZones()
    for i, entry in ipairs(Config.SnowmanLocations) do
        local loc = type(entry) == 'table' and entry.coords or entry
        exports.ox_target:addSphereZone({
            coords  = loc,
            radius  = 2.0,
            name    = 'christmas_snowman_' .. i,
            options = {
                {
                    name     = 'build_snowman_' .. i,
                    label    = T('snowman_build'),
                    icon     = 'fas fa-snowman',
                    distance = 2.0,
                    onSelect = function()
                        if SnowmanTakenUntil[i] and SnowmanTakenUntil[i] > GetGameTimer() then
                            Notify(T('snowman_loc_taken'), 'error')
                            return
                        end
                        CreateThread(function()
                            lib.progressBar({
                                duration     = Config.SnowmanBuildTime,
                                label        = T('snowman_building'),
                                useWhileDead = false,
                                canCancel    = true,
                                anim         = {
                                    dict = Config.Animations.buildSnow.dict,
                                    clip = Config.Animations.buildSnow.anim,
                                },
                            })
                            -- Den faktiske prop/reward kommer fra serverens
                            -- 'snowmanBuilt'-broadcast, ikke herfra direkte -
                            -- serveren er autoritativ for om pladsen reelt er ledig.
                            TriggerServerEvent('mm-christmas:server:buildSnowman', i)
                        end)
                    end
                }
            }
        })
    end
end

-- ── VERDENS-GAVER (findes frit, én gang pr. spiller) ─────
local function SpawnWorldGifts()
    if not Config.WorldGiftsEnabled then return end

    local found = {}
    for _, idx in ipairs(PlayerData.worldGiftsFound or {}) do found[idx] = true end

    for i, coords in ipairs(Config.GiftLocations) do
        if not found[i] then
            local model = GetHashKey(Config.PersonalGiftProp)
            lib.requestModel(model)
            local prop = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
            SetEntityCollision(prop, true, true)
            PlacePropOnGround(prop, coords.x, coords.y, coords.z)
            FreezeEntityPosition(prop, true)
            WorldGiftProps[i] = prop

            exports.ox_target:addLocalEntity(prop, {
                {
                    name     = 'world_gift_' .. i,
                    label    = T('gift_open'),
                    icon     = 'fas fa-gift',
                    distance = 2.0,
                    onSelect = function()
                        CreateThread(function()
                            PlayAnim(Config.Animations.openGift.dict, Config.Animations.openGift.anim, Config.Animations.openGift.duration)
                            TriggerServerEvent('mm-christmas:server:worldGiftFound', i)
                        end)
                    end
                }
            })
        end
    end
end

-- ── PERSONLIGE GAVER (admin-sendt) ───────────────────────
RegisterNetEvent('mm-christmas:client:spawnPersonalGift', function(giftData)
    CreateThread(function()
        local coords = vector3(giftData.coords.x, giftData.coords.y, giftData.coords.z)
        local model  = GetHashKey(Config.PersonalGiftProp)
        lib.requestModel(model)

        local prop = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
        SetEntityCollision(prop, true, true)
        PlacePropOnGround(prop, coords.x, coords.y, coords.z)
        FreezeEntityPosition(prop, true)

        SetNewWaypoint(coords.x, coords.y)
        Notify(T('gift_spawned'), 'success', 6000, 'gift')

        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, 280)
        SetBlipColour(blip, 2)
        SetBlipScale(blip, 1.2)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Personlig Gave 🎁')
        EndTextCommandSetBlipName(blip)

        ActiveGiftProps[giftData.id] = { prop = prop, blip = blip }

        exports.ox_target:addLocalEntity(prop, {
            {
                name     = 'personal_gift_' .. giftData.id,
                label    = T('gift_open'),
                icon     = 'fas fa-gift',
                distance = 2.0,
                onSelect = function()
                    CreateThread(function()
                        PlayAnim(Config.Animations.openGift.dict, Config.Animations.openGift.anim, Config.Animations.openGift.duration)
                        TriggerServerEvent('mm-christmas:server:giftFound', giftData.id)
                    end)
                end
            }
        })
    end)
end)

RegisterNetEvent('mm-christmas:client:removeGift', function(giftId)
    local entry = ActiveGiftProps[giftId]
    if not entry then return end
    ActiveGiftProps[giftId] = nil

    if entry.prop and DoesEntityExist(entry.prop) then
        exports.ox_target:removeLocalEntity(entry.prop, 'personal_gift_' .. giftId)
        DeleteObject(entry.prop)
    end
    if entry.blip then RemoveBlip(entry.blip) end
end)

-- ── DISTANCE TRACKING ────────────────────────────────────
local SEND_INTERVAL = Config.Distance.ReportInterval
local DRIVE_SPEED   = 5.0
local RUN_SPEED     = 1.5

CreateThread(function()
    while true do
        Wait(500)
        if not Shared.IsEventActive() then Wait(60000); goto continue end

        local ped    = cache.ped
        local coords = GetEntityCoords(ped)

        if LastPos then
            local dist = Shared.Distance(coords, LastPos)
            if dist < 200 then -- sanity check (no teleport)
                local speed = GetEntitySpeed(ped)
                local inVeh = IsPedInAnyVehicle(ped, false)

                if inVeh and speed > DRIVE_SPEED then
                    DrivingDistance = DrivingDistance + dist
                elseif not inVeh and speed > RUN_SPEED then
                    RunningDistance = RunningDistance + dist
                end
            end
        end

        LastPos = coords

        local now = GetGameTimer()
        if now - LastSendTime >= SEND_INTERVAL then
            LastSendTime = now
            if DrivingDistance > 0 or RunningDistance > 0 then
                TriggerServerEvent('mm-christmas:server:trackDistance', DrivingDistance, RunningDistance)
                DrivingDistance = 0
                RunningDistance = 0
            end
        end
        ::continue::
    end
end)

-- ── JOIN TRIGGER ─────────────────────────────────────────
local function InitWorld()
    TriggerServerEvent('mm-christmas:server:playerJoin')
    Wait(500)
    if Shared.IsEventActive() then
        SpawnTrees()
        SpawnSnowmanZones()
        SpawnWorldGifts()
    end
end

AddEventHandler('onClientResourceStart', function(res)
    if res ~= RESOURCE then return end
    Wait(2000)
    InitWorld()
end)

CreateThread(function()
    Wait(3000)
    InitWorld()
end)

-- ── CLEANUP ──────────────────────────────────────────────
-- Rydder alt op der ellers ville lække ved resource stop/restart:
-- props, ox_target zones/entities, og blips (blips fjernes IKKE
-- automatisk af FiveM ved resource stop, i modsætning til hvad man
-- kunne forvente).
AddEventHandler('onResourceStop', function(res)
    if res ~= RESOURCE then return end

    SetNuiFocus(false, false)

    for giftId, entry in pairs(ActiveGiftProps) do
        if entry.prop and DoesEntityExist(entry.prop) then
            pcall(function() exports.ox_target:removeLocalEntity(entry.prop, 'personal_gift_' .. giftId) end)
            DeleteObject(entry.prop)
        end
        if entry.blip then RemoveBlip(entry.blip) end
    end

    for i, prop in pairs(TreeProps) do
        if DoesEntityExist(prop) then
            pcall(function() exports.ox_target:removeLocalEntity(prop, 'christmas_tree_' .. i) end)
            DeleteObject(prop)
        end
    end

    for i, prop in pairs(SnowmanProps) do
        if DoesEntityExist(prop) then DeleteObject(prop) end
        pcall(function() exports.ox_target:removeZone('christmas_snowman_' .. i) end)
    end

    for i, prop in pairs(WorldGiftProps) do
        if DoesEntityExist(prop) then
            pcall(function() exports.ox_target:removeLocalEntity(prop, 'world_gift_' .. i) end)
            DeleteObject(prop)
        end
    end
end)
