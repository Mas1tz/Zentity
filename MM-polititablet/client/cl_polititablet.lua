-- ============================================================
--  kc_mdt | client/cl_polititablet.lua
--  State, prop, animation, open/close MDT, GPS sync, commands
-- ============================================================

ESX = exports['es_extended']:getSharedObject()

KCC = KCC or {}

KCC.isOpen      = false
KCC.isLoggedIn  = false
KCC.prop        = nil
KCC.gpsTick     = nil
KCC.lastGPSPos  = nil
KCC.lastVehicle = { netId = nil, seatRole = nil } -- Flådestyring (§22)

-- ─── HELPERS ─────────────────────────────────────────────────
local function SendNUI(action, data)
    SendNUIMessage({ action = action, data = data or {} })
end
KCC.SendNUI = SendNUI

local function HasJobAccess()
    local pdata = ESX.GetPlayerData()
    return pdata and pdata.job and Config.AllowedJobs[pdata.job.name]
end
KCC.HasJobAccess = HasJobAccess

-- ─── PROP & ANIMATION ────────────────────────────────────────
local function SpawnProp()
    if KCC.prop and DoesEntityExist(KCC.prop) then return end
    lib.requestModel(Config.PropModel, 5000)
    lib.requestAnimDict(Config.AnimDict, 5000)

    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    KCC.prop = CreateObject(Config.PropModel, coords.x, coords.y, coords.z + 0.2, true, true, true)
    AttachEntityToEntity(KCC.prop, ped, GetPedBoneIndex(ped, Config.PropBone),
        Config.PropOffset.x, Config.PropOffset.y, Config.PropOffset.z,
        Config.PropRot.x, Config.PropRot.y, Config.PropRot.z,
        true, true, false, true, 1, true)

    TaskPlayAnim(ped, Config.AnimDict, Config.AnimName, Config.AnimBlend, Config.AnimBlend, -1, 49, 0, false, false, false)
    SetModelAsNoLongerNeeded(Config.PropModel)
end

local function RemoveProp()
    if KCC.prop and DoesEntityExist(KCC.prop) then
        DetachEntity(KCC.prop, true, true)
        DeleteEntity(KCC.prop)
    end
    KCC.prop = nil
    ClearPedTasks(PlayerPedId())
end

-- ─── VEHICLE STATE (Flådestyring §22) ─────────────────────────
-- Genbruger GPS-tickets interval i stedet for at starte endnu en
-- thread (§34 — undgå unødvendige loops). Sender KUN et event til
-- serveren når køretøj/sæde reelt ændrer sig, aldrig hver tick.
local function CheckVehicleState(ped)
    local netId, seatRole, label = nil, nil, nil

    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle and vehicle ~= 0 then
            netId = NetworkGetNetworkIdFromEntity(vehicle)
            seatRole = (GetPedInVehicleSeat(vehicle, -1) == ped) and 'driver' or 'passenger'

            local hash = GetEntityModel(vehicle)
            local disp = GetDisplayNameFromVehicleModel(hash)
            local lbl  = GetLabelText(disp)
            label = (lbl ~= '' and lbl ~= 'NULL') and lbl or disp
        end
    end

    if netId ~= KCC.lastVehicle.netId or seatRole ~= KCC.lastVehicle.seatRole then
        KCC.lastVehicle = { netId = netId, seatRole = seatRole }
        TriggerServerEvent('kcmdt:updateVehicleState', label, netId, seatRole)
    end
end

-- ─── GPS SYNC ────────────────────────────────────────────────
local function StartGPS()
    if KCC.gpsTick then return end
    KCC.gpsTick = SetInterval(function()
        if not KCC.isLoggedIn then return end
        local ped = PlayerPedId()
        if not ped or ped == 0 then return end

        CheckVehicleState(ped)

        local c = GetEntityCoords(ped)
        -- Klient-side throttle: skip hvis vi ikke har bevæget os
        if KCC.lastGPSPos then
            local dx, dy = c.x - KCC.lastGPSPos.x, c.y - KCC.lastGPSPos.y
            if (dx*dx + dy*dy) < 25.0 then return end  -- mindre end 5m
        end
        KCC.lastGPSPos = { x = c.x, y = c.y, z = c.z }
        TriggerServerEvent('kcmdt:updateGPS', c.x, c.y, c.z)
    end, Config.GPSSyncInterval)
end
KCC.StartGPS = StartGPS

local function StopGPS()
    if KCC.gpsTick then
        ClearInterval(KCC.gpsTick)
        KCC.gpsTick = nil
    end
    KCC.lastGPSPos = nil
    KCC.lastVehicle = { netId = nil, seatRole = nil }
end
KCC.StopGPS = StopGPS

-- ─── OPEN / CLOSE ────────────────────────────────────────────
local function OpenMDT()
    if KCC.isOpen then return end
    if not HasJobAccess() then
        lib.notify({ title='MDT', description='Du har ikke adgang til MDT.', type='error' })
        return
    end
    KCC.isOpen = true
    SpawnProp()
    SetNuiFocus(true, true)
    SendNUI('open', { resourceName = GetCurrentResourceName() })
end
KCC.OpenMDT = OpenMDT

local function CloseMDT()
    if not KCC.isOpen then return end
    KCC.isOpen = false
    RemoveProp()
    SetNuiFocus(false, false)
    SendNUI('close', {})
end
KCC.CloseMDT = CloseMDT

local function ToggleMDT()
    if KCC.isOpen then CloseMDT() else OpenMDT() end
end
KCC.ToggleMDT = ToggleMDT

-- ─── COMMAND & KEYBIND ───────────────────────────────────────
RegisterCommand(Config.Command, function() ToggleMDT() end, false)
RegisterKeyMapping(Config.Command, 'Åben/Luk MDT', 'keyboard', Config.Keybind)

-- ─── CLEANUP ─────────────────────────────────────────────────
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if KCC.isOpen then
        SetNuiFocus(false, false)
        RemoveProp()
    end
    StopGPS()
end)

-- Hvis spilleren dør (panic-flugt etc.) — luk MDT
AddEventHandler('esx:onPlayerDeath', function()
    if KCC.isOpen then CloseMDT() end
end)