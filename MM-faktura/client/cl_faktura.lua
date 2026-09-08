-- ============================================================
--  client/cl_faktura.lua  –  Faktura Tablet V2
-- ============================================================

local isTabletOpen = false
local tabletProp = nil
local playerJob = nil
local Framework = Config.Framework

if Framework == "auto" then
    Framework = GetResourceState("qb-core") == "started" and "qb" or "esx"
end

local QBCore, ESX = nil, nil
if Framework == "esx" then ESX = exports["es_extended"]:getSharedObject()
elseif Framework == "qb" then QBCore = exports['qb-core']:GetCoreObject() end

-- ============================================================
--  NOTIFY
-- ============================================================
local function notify(data)
    if type(data) ~= "table" then data = { type = 'inform', text = tostring(data) } end
    if exports.ox_lib then
        exports.ox_lib:notify({ type = data.type or "inform", description = data.text, position = 'center-right' })
    else
        TriggerEvent('chat:addMessage', { args = { "[Faktura]", data.text } })
    end
    -- Vis den også som en toast inde i selve tabletten, så man ikke er afhængig
    -- af at ox_lib-notifikationen er synlig/placeret et sted man lægger mærke til.
    SendNUIMessage({ action = 'toast', message = data.text, type = data.type })
end

RegisterNUICallback('localNotify', function(data, cb) notify(data) cb('ok') end)

-- ============================================================
--  JOB TRACKING
-- ============================================================
local function updateInvoices() TriggerServerEvent('mm_faktura:server:getInvoices') end

if Framework == "esx" then
    RegisterNetEvent('esx:playerLoaded', function(xPlayer) playerJob = xPlayer.job.name updateInvoices() end)
    RegisterNetEvent('esx:setJob', function(job) playerJob = job.name updateInvoices() end)
else
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() playerJob = QBCore.Functions.GetPlayerData().job.name updateInvoices() end)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) playerJob = job.name updateInvoices() end)
end

local function getMyJob()
    if Framework == "esx" then
        local pdata = ESX.GetPlayerData()
        return pdata.job and pdata.job.name or "unemployed"
    else
        local pdata = QBCore.Functions.GetPlayerData()
        return pdata.job and pdata.job.name or "unemployed"
    end
end

-- ============================================================
--  PROP
-- ============================================================
local function spawnTabletProp()
    if tabletProp then return end
    local ped = cache.ped or PlayerPedId()
    local propModel = `prop_cs_tablet`
    lib.requestModel(propModel, 2000)
    local coords = GetEntityCoords(ped)
    tabletProp = CreateObject(propModel, coords.x, coords.y, coords.z + 0.2, true, true, false)
    AttachEntityToEntity(
        tabletProp, ped, GetPedBoneIndex(ped, 28422),
        Config.PropPlacement[1], Config.PropPlacement[2], Config.PropPlacement[3],
        Config.PropPlacement[4], Config.PropPlacement[5], Config.PropPlacement[6],
        true, true, false, true, 1, true
    )
    lib.requestAnimDict("amb@code_human_in_bus_passenger_idles@female@tablet@base", 2000)
    TaskPlayAnim(ped, "amb@code_human_in_bus_passenger_idles@female@tablet@base", "base", 3.0, 3.0, -1, 49, 0, false, false, false)
end

local function deleteTabletProp()
    if tabletProp then
        if DoesEntityExist(tabletProp) then
            DetachEntity(tabletProp, true, true)
            DeleteEntity(tabletProp)
        end
        tabletProp = nil
    end
    ClearPedTasks(cache.ped or PlayerPedId())
end

-- ============================================================
--  NEARBY PLAYERS (auto-opdaterende liste mens tabletten er åben)
-- ============================================================
local NEARBY_RADIUS = 15.0

RegisterNUICallback('setVisibility', function(data, cb)
    local radius = tonumber(data.radius)
    if radius and radius > 0 then NEARBY_RADIUS = radius end
    cb({ ok = true, radius = NEARBY_RADIUS })
end)

local function pushNearbyPlayers()
    local myPed = cache.ped or PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local list = {}

    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local ped = GetPlayerPed(pid)
            if DoesEntityExist(ped) then
                local dist = #(myCoords - GetEntityCoords(ped))
                if dist <= NEARBY_RADIUS then
                    table.insert(list, {
                        serverId = GetPlayerServerId(pid),
                        name     = GetPlayerName(pid),
                        distance = math.floor(dist * 10) / 10,
                    })
                end
            end
        end
    end

    table.sort(list, function(a, b) return a.distance < b.distance end)
    SendNUIMessage({ action = "nearbyPlayers", players = list })
end

CreateThread(function()
    while true do
        Wait(3000)
        if isTabletOpen then pushNearbyPlayers() end
    end
end)

-- ============================================================
--  OPEN / CLOSE
-- ============================================================

local function openTablet(initialData)
    if isTabletOpen then return end
    isTabletOpen = true
    spawnTabletProp()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "open", data = initialData or {}, config = Config })
    pushNearbyPlayers()
    TriggerServerEvent('mm_faktura:server:whoAmI')
end

local function closeTablet()
    if not isTabletOpen then return end
    isTabletOpen = false
    SetNuiFocus(false, false)
    deleteTabletProp()
    SendNUIMessage({ action = "close" })
end

-- Andre resources kan åbne tabletten for spilleren via exports['mm-faktura']:OpenTablet(src, data)
RegisterNetEvent('mm_faktura:client:externalOpen', function(initialData)
    local myJob = getMyJob()
    local canSend = Config.BillingJobs[myJob] ~= nil
    openTablet({ canSend = canSend, job = canSend and myJob or nil })
end)

-- ============================================================
--  NUI CALLBACKS
-- ============================================================
RegisterNUICallback('close', function(_, cb) closeTablet() cb('ok') end)
RegisterNUICallback('escape', function(_, cb) closeTablet() cb('ok') end)

RegisterNUICallback('searchPlayer', function(data, cb)
    local id = tonumber(data.id)
    if id then TriggerServerEvent('mm_faktura:server:getPlayerInfo', id) end
    cb({ success = id ~= nil })
end)

RegisterNUICallback('selectNearby', function(data, cb)
    local id = tonumber(data.id)
    if id then TriggerServerEvent('mm_faktura:server:getPlayerInfo', id) end
    cb({ success = id ~= nil })
end)

RegisterNUICallback('sendInvoice', function(data, cb)
    TriggerServerEvent('mm_faktura:server:sendInvoice', data)
    cb({ ok = true })
end)

RegisterNUICallback('requestInvoices', function(_, cb) updateInvoices() cb({ ok = true }) end)

RegisterNUICallback('payInvoice', function(data, cb)
    TriggerServerEvent('mm_faktura:server:payInvoice', data.id)
    cb({ ok = true })
end)

RegisterNUICallback('deleteInvoice', function(data, cb)
    TriggerServerEvent('mm_faktura:server:deleteInvoice', data.id)
    cb({ ok = true })
end)

RegisterNUICallback('requestCategories', function(data, cb)
    TriggerServerEvent('mm_faktura:server:requestCategories', data.job)
    cb({ ok = true })
end)

RegisterNUICallback('addItem', function(data, cb)
    TriggerServerEvent('mm_faktura:server:addItem', data.job, data.group, data.label, data.price)
    cb({ ok = true })
end)

RegisterNUICallback('editItem', function(data, cb)
    TriggerServerEvent('mm_faktura:server:editItem', data.job, data.catId, data.label, data.price)
    cb({ ok = true })
end)

RegisterNUICallback('deleteItem', function(data, cb)
    TriggerServerEvent('mm_faktura:server:deleteItem', data.job, data.catId)
    cb({ ok = true })
end)

RegisterNUICallback('deleteGroup', function(data, cb)
    TriggerServerEvent('mm_faktura:server:deleteGroup', data.job, data.group)
    cb({ ok = true })
end)

-- ============================================================
--  SERVER → CLIENT → NUI
-- ============================================================
RegisterNetEvent('mm_faktura:client:playerInfo', function(targetId, info)
    SendNUIMessage({ action = 'playerInfo', playerId = targetId, info = info })
end)
RegisterNetEvent('mm_faktura:client:playerSummary', function(targetId, summary)
    SendNUIMessage({ action = 'playerSummary', playerId = targetId, summary = summary })
end)
RegisterNetEvent('mm_faktura:client:invoicesUpdated', function(list)
    SendNUIMessage({ action = 'invoicesList', invoices = list or {} })
end)
RegisterNetEvent('mm_faktura:client:notify', function(data) notify(data) end)
RegisterNetEvent('mm_faktura:client:categoriesData', function(job, categories, canManage)
    SendNUIMessage({ action = 'categoriesData', job = job, categories = categories, canManage = canManage })
end)

-- Fortæller NUI'en hvilke jobs spilleren selv kan administrere kategorier for
RegisterNetEvent('mm_faktura:client:permissions', function(perms)
    SendNUIMessage({ action = 'permissions', data = perms })
end)

-- ============================================================
--  COMMAND + KEYBIND
-- ============================================================
RegisterCommand('faktura', function()
    local myJob = getMyJob()
    local canSend = Config.BillingJobs[myJob] ~= nil
    openTablet({ canSend = canSend, job = canSend and myJob or nil })
end, false)
RegisterKeyMapping('faktura', 'Åbn Faktura Tablet', 'keyboard', 'F7')

-- ============================================================
--  CLEANUP
-- ============================================================
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        closeTablet()
    end
end)
