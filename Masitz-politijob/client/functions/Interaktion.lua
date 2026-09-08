-- ============================================================
-- MM-PolitiJob – client/functions/actions.lua
-- GSR, ID-check, visitering, håndjern-target, eskort-target
-- Alle actions: server-valideret, afstand-tjekket, anti-self
-- ============================================================

-- ── HJÆLPERE ─────────────────────────────────────────────────

local function GetLocalServerId()
    return GetPlayerServerId(PlayerId())
end

-- Tjek om target er valid til en action
-- Returnerer false + notif hvis ugyldig
local function ValidateTarget(targetServerId)
    -- Anti-self
    if targetServerId == GetLocalServerId() then
        lib.notify({ title = 'Fejl', description = 'Du kan ikke bruge dette på dig selv.', type = 'error', position = 'center-right' })
        return false
    end

    -- Job check
    if not MM.Framework.IsPolice() then
        lib.notify({ title = 'Fejl', description = 'Du er ikke ansat i politiet.', type = 'error', position = 'center-right' })
        return false
    end

    -- Afstand
    local targetPlayer = GetPlayerFromServerId(targetServerId)
    if targetPlayer == -1 then
        lib.notify({ title = 'Fejl', description = 'Spilleren ikke fundet.', type = 'error', position = 'center-right' })
        return false
    end

    local targetPed = GetPlayerPed(targetPlayer)
    if not DoesEntityExist(targetPed) then return false end

    local dist = #(GetEntityCoords(cache.ped) - GetEntityCoords(targetPed))
    if dist > Config.MaxActionDistance then
        lib.notify({ title = 'Fejl', description = 'Spilleren er for langt væk.', type = 'error', position = 'center-right' })
        return false
    end

    return true
end

-- Tjek om target er død
local function IsTargetDead(targetServerId)
    local tp = GetPlayerPed(GetPlayerFromServerId(targetServerId))
    return IsEntityDead(tp) or IsPedDeadOrDying(tp, true)
end

-- ── TARGET REGISTRERING ───────────────────────────────────────
-- Sættes op i et separat CreateThread så det kun kører én gang
-- og kan genregistreres hvis ox_target genstarter.

local targetsRegistered = false

MM.RegisterPoliceTargets = function()
    if targetsRegistered then return end
    targetsRegistered = true

    -- ─────────────────────────────────────────────
-- VEHICLE TARGETS
-- ─────────────────────────────────────────────

exports.ox_target:addGlobalVehicle({

    -- DV / Fjern køretøj
    {
        name = 'mm_vehicle_dv',
        label = '🗑️ Fjern køretøj',
        icon = 'fa-solid fa-car-burst',
        distance = 3.0,

        canInteract = function(entity)
            if not MM.Framework.IsPolice() then return false end
            return DoesEntityExist(entity)
        end,

        onSelect = function(data)
            local veh = data.entity

            lib.progressCircle({
                duration = 3000,
                label = 'Fjerner køretøj...',
                position = 'bottom',
                canCancel = true,
                disable = {
                    move = true,
                    combat = true
                },
            }, function(cancelled)

                if cancelled then return end

                if DoesEntityExist(veh) then
                    SetEntityAsMissionEntity(veh, true, true)
                    DeleteVehicle(veh)

                    lib.notify({
                        title = 'Politi',
                        description = 'Køretøj fjernet.',
                        type = 'success', position = 'center-right' })
                end
            end)
        end
    },

    -- Impound
    {
        name = 'mm_vehicle_impound',
        label = '🚓 Impound køretøj',
        icon = 'fa-solid fa-warehouse',
        distance = 3.0,

        canInteract = function(entity)
            if not MM.Framework.IsPolice() then return false end
            return DoesEntityExist(entity)
        end,

        onSelect = function(data)

            local input = lib.inputDialog('Impound køretøj', {
                {
                    type = 'input',
                    label = 'Årsag',
                    required = true
                }
            })

            if not input then return end

            local veh = data.entity
            local plate = GetVehicleNumberPlateText(veh)

            lib.progressCircle({
                duration = 5000,
                label = 'Impounder køretøj...',
                position = 'bottom',
                canCancel = false
            }, function()

                TriggerServerEvent('mm_police:server:impoundVehicle', plate, input[1])

                SetEntityAsMissionEntity(veh, true, true)
                DeleteVehicle(veh)

                lib.notify({
                    title = 'Impound',
                    description = 'Køretøjet blev impoundet.',
                    type = 'success', position = 'center-right' })
            end)
        end
    },

    -- Vehicle Info
    {
        name = 'mm_vehicle_info',
        label = '📋 Køretøjsinformation',
        icon = 'fa-solid fa-circle-info',
        distance = 3.0,

        canInteract = function(entity)
            if not MM.Framework.IsPolice() then return false end
            return DoesEntityExist(entity)
        end,

        onSelect = function(data)

            local veh = data.entity

            local plate = GetVehicleNumberPlateText(veh)
            local model = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
            local speed = math.floor(GetEntitySpeed(veh) * 3.6)

            lib.alertDialog({
                header = '🚓 Køretøjsinformation',
                content = ('**Nummerplade:** %s\n**Model:** %s\n**Hastighed:** %s KM/T')
                    :format(plate, model, speed),
                centered = true,
                cancel = false
            })
        end
    },

})

    exports.ox_target:addGlobalPlayer({

        -- ── HÅNDJERN (SOFT) ──────────────────────────────────
        {
            name    = 'mm_handcuff_soft',
            label   = '🔗 Håndjern (bløde)',
            icon    = 'fa-solid fa-handcuffs',
            distance = Config.HandcuffMaxDistance,
            canInteract = function(entity, dist, coords, name, bone)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId == GetLocalServerId() then return false end
                if not MM.Framework.IsPolice() then return false end
                if IsTargetDead(targetServerId) then return false end
                -- Vis kun hvis IKKE allerede håndjernet
                local _p = GetPlayerFromServerId(targetServerId)
                if _p == -1 then return false end
                local tState = Player(_p).state
                return not (tState and tState.isHandcuffed)
            end,
            onSelect = function(data)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(data.entity))
                if not ValidateTarget(targetServerId) then return end
                TriggerServerEvent('mm_police:server:handcuff', targetServerId, 'soft')
            end,
        },

        -- ── HÅNDJERN (HARD) ──────────────────────────────────
        {
            name    = 'mm_handcuff_hard',
            label   = '⛓️ Håndjern (hårde)',
            icon    = 'fa-solid fa-lock',
            distance = Config.HandcuffMaxDistance,
            canInteract = function(entity, dist, coords, name, bone)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId == GetLocalServerId() then return false end
                if not MM.Framework.IsPolice() then return false end
                if IsTargetDead(targetServerId) then return false end
                local _p = GetPlayerFromServerId(targetServerId)
                if _p == -1 then return false end
                local tState = Player(_p).state
                return tState and tState.isHandcuffed and tState.handcuffMode ~= 'hard'
            end,
            onSelect = function(data)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(data.entity))
                if not ValidateTarget(targetServerId) then return end
                TriggerServerEvent('mm_police:server:handcuff', targetServerId, 'hard')
            end,
        },

        -- ── FJERN HÅNDJERN ────────────────────────────────────
        {
            name    = 'mm_uncuff',
            label   = '🔓 Fjern håndjern',
            icon    = 'fa-solid fa-unlock',
            distance = Config.HandcuffMaxDistance,
            canInteract = function(entity, dist, coords, name, bone)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId == GetLocalServerId() then return false end
                if not MM.Framework.IsPolice() then return false end
                local _p = GetPlayerFromServerId(targetServerId)
                if _p == -1 then return false end
                local tState = Player(_p).state
                return tState and tState.isHandcuffed == true
            end,
            onSelect = function(data)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(data.entity))
                if not ValidateTarget(targetServerId) then return end
                TriggerServerEvent('mm_police:server:handcuff', targetServerId, nil)
            end,
        },

        -- ── ESKORT ───────────────────────────────────────────
        {
            name    = 'mm_escort_start',
            label   = '🚶 Start eskort',
            icon    = 'fa-solid fa-person-walking',
            distance = Config.HandcuffMaxDistance,
            canInteract = function(entity, dist, coords, name, bone)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId == GetLocalServerId() then return false end
                if not MM.Framework.IsPolice() then return false end
                if IsTargetDead(targetServerId) then return false end
                local _p = GetPlayerFromServerId(targetServerId)
                if _p == -1 then return false end
                local tState = Player(_p).state
                return tState and tState.isHandcuffed and not tState.isEscorted
            end,
            onSelect = function(data)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(data.entity))
                if not ValidateTarget(targetServerId) then return end
                TriggerServerEvent('mm_police:server:escort', targetServerId, true)
            end,
        },

        -- ── STOP ESKORT ──────────────────────────────────────
        {
            name    = 'mm_escort_stop',
            label   = '⛔ Stop eskort',
            icon    = 'fa-solid fa-person-walking-arrow-right',
            distance = Config.HandcuffMaxDistance,
            canInteract = function(entity, dist, coords, name, bone)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId == GetLocalServerId() then return false end
                if not MM.Framework.IsPolice() then return false end
                local _p = GetPlayerFromServerId(targetServerId)
                if _p == -1 then return false end
                local tState = Player(_p).state
                return tState and tState.isEscorted == true
            end,
            onSelect = function(data)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(data.entity))
                if not ValidateTarget(targetServerId) then return end
                TriggerServerEvent('mm_police:server:escort', targetServerId, false)
            end,
        },

        -- ── ID CHECK ─────────────────────────────────────────
        {
            name    = 'mm_id_check',
            label   = '🪪 Tjek ID',
            icon    = 'fa-solid fa-id-card',
            distance = Config.MaxActionDistance,
            canInteract = function(entity, dist, coords, name, bone)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId == GetLocalServerId() then return false end
                return MM.Framework.IsPolice()
            end,
            onSelect = function(data)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(data.entity))
                if not ValidateTarget(targetServerId) then return end
                TriggerServerEvent('mm_police:server:idCheck', targetServerId)
            end,
        },

        -- ── GSR TEST ─────────────────────────────────────────
        {
            name    = 'mm_gsr',
            label   = '🔬 GSR Test',
            icon    = 'fa-solid fa-microscope',
            distance = Config.MaxActionDistance,
            canInteract = function(entity, dist, coords, name, bone)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId == GetLocalServerId() then return false end
                return MM.Framework.IsPolice()
            end,
            onSelect = function(data)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(data.entity))
                if not ValidateTarget(targetServerId) then return end

                lib.progressCircle({
                    duration    = 3000,
                    label       = 'Tager GSR prøve...',
                    position    = 'bottom',
                    useWhileDead = false,
                    canCancel   = true,
                    anim = { dict = 'amb@medic@standing@kneel@base', clip = 'base' },
                }, function(cancelled)
                    if not cancelled then
                        TriggerServerEvent('mm_police:server:gsrTest', targetServerId)
                    end
                end)
            end,
        },

        -- ── VISITERING ───────────────────────────────────────
        {
            name    = 'mm_search',
            label   = '🔍 Visitér',
            icon    = 'fa-solid fa-magnifying-glass',
            distance = Config.MaxActionDistance,
            canInteract = function(entity, dist, coords, name, bone)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(entity))
                if not targetServerId or targetServerId == GetLocalServerId() then return false end
                if not MM.Framework.IsPolice() then return false end
                if IsTargetDead(targetServerId) then return false end
                -- FIX: Kun på håndjernede spillere
                local _p = GetPlayerFromServerId(targetServerId)
                if _p == -1 then return false end
                local tState = Player(_p).state
                return tState and tState.isHandcuffed == true
            end,
            onSelect = function(data)
                local targetServerId = GetPlayerServerId(
                    NetworkGetPlayerIndexFromPed(data.entity))
                if not ValidateTarget(targetServerId) then return end

                lib.progressCircle({
                    duration    = 3000,
                    label       = 'Visiterer...',
                    position    = 'bottom',
                    useWhileDead = false,
                    canCancel   = true,
                    anim = { dict = 'anim@mp_radio@garage@stand@ps3@base', clip = 'base' },
                }, function(cancelled)
                    if not cancelled then
                        TriggerServerEvent('mm_police:server:search', targetServerId)
                    end
                end)
            end,
        },

    })
end

-- ── GSR TRACKING (CLIENT) ────────────────────────────────────
-- GSR (Gun Shot Residue) gælder ALLE spillere, ikke kun politi -
-- enhver der skyder kan senere blive testet af politiet.
CreateThread(function()
    local lastShot = 0
    while true do
        Wait(500)
        if IsPedShooting(cache.ped) then
            local now = GetGameTimer()
            if now - lastShot > 2000 then
                lastShot = now
                TriggerServerEvent('mm_police:server:setGSR')
            end
        end
    end
end)

-- Målregistrering (MM.RegisterPoliceTargets) bootstrappes centralt
-- fra client/main.lua, ikke her - for at undgå to identiske
-- ventetråde, der begge forsøger at gøre det samme ved opstart.

-- ── ID CHECK RESULT (fra server) ─────────────────────────────
RegisterNetEvent('mm_police:client:idResult', function(data)
    if not data then return end
    lib.alertDialog({
        header  = '🪪 ID Kontrol',
        content = ('**Navn:** %s\n**Identifikator:** %s\n**Job:** %s\n**Grade:** %s')
            :format(data.name, data.identifier, data.job, data.grade),
        centered = true,
        cancel  = false,
    })
end)

-- ── VISITERING RESULT ────────────────────────────────────────
RegisterNetEvent('mm_police:client:searchResult', function(targetId, targetName)
    lib.notify({
        title       = 'Visitering',
        description = ('Du visiterer %s – inventory åbner.'):format(targetName),
        type        = 'inform',
        position    = 'center-right',
    })
    -- FIX: ox_inventory's 'player' inventory-type forventer target-
    -- spillerens server-ID, ikke navnet på spilleren.
    exports.ox_inventory:openInventory('player', targetId)
end)