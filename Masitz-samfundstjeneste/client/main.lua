--[[
    client/main.lua — NUI open/close-mekanikken + videreformidling af alle
    staff/owner-callbacks til serveren. Selve gameplay-flowet (service,
    tasks, anti-escape, aktivitet) ligger i de dedikerede filer for at
    holde dette modul fokuseret på NUI-kommunikation.
]]

local dashboardOpen = false

-- Delt med client/tasks.lua (samme resource/Lua-state) - en client-side
-- spejling af active_tasks, UDELUKKENDE brugt til at afgøre om [E]-
-- prompten (lib.showTextUI) må vises. Autoriteten forbliver 100% server-
-- side; denne værdi styrer aldrig om en opgave rent faktisk godkendes.
PlayerTaskState = { activeTasks = 0 }

local function CloseDashboard()
    if not dashboardOpen then return end

    dashboardOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- Spilleren vælger ALDRIG selv et arbejdssted, så dashboardet får ikke
-- længere en sites-liste fra serveren — kun rolle, egne tal og status.
RegisterNetEvent('mm_sf:client:openDashboard', function(role, playerData)
    PlayerTaskState.activeTasks = tonumber(playerData and playerData.active_tasks) or 0

    if dashboardOpen then return end
    dashboardOpen = true

    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        role = role,
        player = playerData,
        inService = Service.active,
    })
end)

-- Live-opdatering: sendes hver gang staff/owner/task-engine/trust factor
-- ændrer noget for denne spiller, uanset om dashboardet er åbent.
RegisterNetEvent('mm_sf:client:playerUpdate', function(playerData)
    PlayerTaskState.activeTasks = tonumber(playerData and playerData.active_tasks) or 0
    SendNUIMessage({ action = 'playerUpdate', player = playerData })
end)

-- Kaldes fra JS (fx ved ESC eller et luk-ikon)
RegisterNUICallback('close', function(_, cb)
    CloseDashboard()
    cb('ok')
end)

RegisterNUICallback('getHistory', function(_, cb)
    local history = lib.callback.await('mm_sf:server:getHistory', false)
    cb(history or {})
end)

-- ------------------------------------------------------------
-- STAFF CALLBACKS — videresender blot til serveren. Al reel validering
-- (er man Staff/Owner, findes spilleren, er antallet gyldigt) sker
-- server-side; en manipuleret NUI kan i bedste fald kalde disse forgæves.
-- ------------------------------------------------------------
local function ForwardCallback(serverEvent)
    return function(data, cb)
        local ok, err, profile = lib.callback.await(serverEvent, false, data)
        cb({ ok = ok, error = err, profile = profile })
    end
end

RegisterNUICallback('staffGetOnlinePlayers', function(_, cb)
    cb(lib.callback.await('mm_sf:server:staffGetOnlinePlayers', false) or {})
end)

RegisterNUICallback('staffSearch', function(data, cb)
    cb(lib.callback.await('mm_sf:server:staffSearch', false, data.query) or {})
end)

RegisterNUICallback('staffGetProfile', function(data, cb)
    cb(lib.callback.await('mm_sf:server:staffGetProfile', false, data.identifier))
end)

RegisterNUICallback('staffGetHistory', function(data, cb)
    cb(lib.callback.await('mm_sf:server:staffGetHistory', false, data.identifier) or {})
end)

RegisterNUICallback('staffGiveService', ForwardCallback('mm_sf:server:staffGiveService'))
RegisterNUICallback('staffRemoveTasks', ForwardCallback('mm_sf:server:staffRemoveTasks'))
RegisterNUICallback('staffSetTasks', ForwardCallback('mm_sf:server:staffSetTasks'))
RegisterNUICallback('staffRelease', ForwardCallback('mm_sf:server:staffRelease'))

-- ------------------------------------------------------------
-- OWNER CALLBACKS
-- ------------------------------------------------------------
RegisterNUICallback('ownerGetSettings', function(_, cb)
    cb(lib.callback.await('mm_sf:server:ownerGetSettings', false) or {})
end)

RegisterNUICallback('ownerGetTasks', function(_, cb)
    cb(lib.callback.await('mm_sf:server:ownerGetTasks', false) or {})
end)

RegisterNUICallback('ownerUpdateSetting', function(data, cb)
    local ok, err, settings = lib.callback.await('mm_sf:server:ownerUpdateSetting', false, data)
    cb({ ok = ok, error = err, settings = settings })
end)

RegisterNUICallback('ownerToggleTask', function(data, cb)
    local ok, err = lib.callback.await('mm_sf:server:ownerToggleTask', false, data)
    cb({ ok = ok, error = err })
end)

RegisterNUICallback('ownerGetStatistics', function(_, cb)
    cb(lib.callback.await('mm_sf:server:ownerGetStatistics', false))
end)

RegisterNUICallback('ownerGetAuditLog', function(data, cb)
    cb(lib.callback.await('mm_sf:server:ownerGetAuditLog', false, data and data.offset) or {})
end)

-- ------------------------------------------------------------
-- CLEANUP
-- Uden dette ville en resource-restart mens dashboardet er åbent kunne
-- efterlade spilleren med NUI-fokus og synlig cursor permanent.
-- ------------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if dashboardOpen then
        SetNuiFocus(false, false)
        dashboardOpen = false
    end
end)
