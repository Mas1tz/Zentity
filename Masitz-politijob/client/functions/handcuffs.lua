-- ============================================================
--  MM-PolitiJob – client/functions/handcuffs.lua  v2
-- ============================================================

local ANIM_DICT  = 'mp_arresting'
local ANIM_NAME  = 'idle'
local cuffProp   = nil
local cuffActive = false

-- Forudindlæs dict ved resource start
CreateThread(function()
    lib.requestAnimDict(ANIM_DICT)
end)

-- ── PROP ─────────────────────────────────────────────────────
local function AttachCuffProp(ped)
    if cuffProp and DoesEntityExist(cuffProp) then return end
    cuffProp = nil
    lib.requestModel(Config.HandcuffProp)
    local hash   = GetHashKey(Config.HandcuffProp)
    local coords = GetEntityCoords(ped)
    local prop   = CreateObject(hash, coords.x, coords.y, coords.z, true, true, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 60309),
        0.0, 0.035, 0.06, 280.0, 200.0, 0.0,
        true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
    cuffProp = prop
end

local function DetachCuffProp()
    if cuffProp and DoesEntityExist(cuffProp) then
        DetachEntity(cuffProp, true, false)
        DeleteObject(cuffProp)
    end
    cuffProp = nil
end

-- ── CLEANUP ──────────────────────────────────────────────────
local function Cleanup()
    local ped = cache.ped
    cuffActive = false
    FreezeEntityPosition(ped, false)
    SetEnableHandcuffs(ped, false)
    DisablePlayerFiring(ped, false)
    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    SetPedCanPlayGestureAnims(ped, true)
    DisplayRadar(true)
    ClearPedTasks(ped)
    DetachCuffProp()
end

-- ── CUFF LOOP ────────────────────────────────────────────────
local function StartCuffLoop(mode)
    if cuffActive then return end
    cuffActive = true

    CreateThread(function()
        while cuffActive do
            local ped     = cache.ped
            -- FIX 4: mode læses fra statebag hver frame — hard upgrade virker nu
            local curMode = LocalPlayer.state.handcuffMode or mode

            -- REWORK: hvis target er død/ragdolling må vi IKKE blive ved med
            -- at kalde TaskPlayAnim hver eneste frame — animationen kan aldrig
            -- starte på en død ped, så den gamle kode spammede natives i et
            -- Wait(0)-loop i hele dødsperioden (unødig CPU-brug + visuel
            -- konflikt med dødsanimationen/ragdoll). Vi springer al
            -- håndjern-håndhævelse over mens død og løser blot op for evt.
            -- freeze, så liget ikke hænger fastfrosset.
            local isDead = IsEntityDead(ped) or IsPedDeadOrDying(ped, true)
            if isDead then
                FreezeEntityPosition(ped, false)
                Wait(500)
                goto continue
            end

            -- FIX 3: animation genstarter KUN hvis den er stoppet
            if not IsEntityPlayingAnim(ped, ANIM_DICT, ANIM_NAME, 3) then
                if HasAnimDictLoaded(ANIM_DICT) then
                    TaskPlayAnim(ped, ANIM_DICT, ANIM_NAME, 8.0, -8.0, -1, 49, 0, false, false, false)
                end
            end

            -- FIX 5: weapon tvinges i loop — forhindrer weapon exploit
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)

            DisableControlAction(0, 24,  true)
            DisableControlAction(0, 25,  true)
            DisableControlAction(0, 37,  true)
            DisableControlAction(0, 44,  true)
            DisableControlAction(0, 45,  true)
            DisableControlAction(0, 140, true)
            DisableControlAction(0, 141, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(0, 263, true)
            DisableControlAction(0, 257, true)
            DisableControlAction(0, 289, true)
            DisableControlAction(0, 170, true)
            DisableControlAction(0, 23,  true)
            DisableControlAction(0, 75,  true)
            DisableControlAction(0, 21,  true) -- ingen sprint

            if curMode == 'hard' then
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 34, true)

                -- REWORK: FreezeEntityPosition på en ped der sidder i et
                -- køretøj er en kendt kilde til desync/rubber-banding, fordi
                -- klienten fryser ped'en lokalt mens køretøjets netværks-sync
                -- fortsætter med at flytte den. Er man i et køretøj, låser vi
                -- i stedet selve køretøjets kontroller, så en hårdt-håndjernet
                -- passager ikke kan køre bilen.
                if IsPedInAnyVehicle(ped, false) then
                    FreezeEntityPosition(ped, false)
                    DisableControlAction(0, 59, true) -- VehicleMoveLeftRight
                    DisableControlAction(0, 60, true) -- VehicleMoveUpDown
                    DisableControlAction(0, 63, true) -- VehicleFlyThrottleUp / steer
                    DisableControlAction(0, 64, true) -- VehicleFlyThrottleDown
                    DisableControlAction(0, 71, true) -- VehicleAccelerate
                    DisableControlAction(0, 72, true) -- VehicleBrake
                elseif not IsEntityAttached(ped) then
                    FreezeEntityPosition(ped, true)
                end
            else
                FreezeEntityPosition(ped, false)
            end

            ::continue::
            Wait(0)
        end

        -- Loop stoppet — kør cleanup
        Cleanup()
    end)
end

-- ── RESTART RECOVERY ─────────────────────────────────────────
-- Handcuff-state lever i en statebag der IKKE nulstilles ved resource
-- restart. Uden dette ville en spiller der er håndjernet under en
-- restart ende med isHandcuffed = true i statebaggen, men ingen
-- lokal loop der faktisk begrænser dem (permanent desynkroniseret
-- broken state indtil næste håndjern-event bliver trigget).
CreateThread(function()
    Wait(2000) -- vent på at statebags er synkroniseret efter script-load
    if LocalPlayer.state.isHandcuffed then
        local mode = LocalPlayer.state.handcuffMode
        local ped  = cache.ped

        SetEnableHandcuffs(ped, true)
        DisablePlayerFiring(ped, true)
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        SetPedCanPlayGestureAnims(ped, false)
        DisplayRadar(false)
        AttachCuffProp(ped)
        StartCuffLoop(mode)
    end
end)

-- ── HANDCUFF EVENT ────────────────────────────────────────────
RegisterNetEvent('mm_police:client:handcuff', function(state, mode)
    -- FIX 1: brug StateBag ikke MM.State — nulstilles ikke ved resource restart
    local curState = LocalPlayer.state.isHandcuffed or false
    local curMode  = LocalPlayer.state.handcuffMode

    -- FIX 2: tjek BEGGE — ellers blokeres hard-upgrade (state=true == true → return)
    if state == curState and mode == curMode then return end

    MM.State.SetHandcuffed(state, mode)

    if state then
        local ped = cache.ped

        -- FIX 3: anim dict load er async — SKAL køres i thread
        CreateThread(function()
            if not HasAnimDictLoaded(ANIM_DICT) then
                lib.requestAnimDict(ANIM_DICT)
            end
            if HasAnimDictLoaded(ANIM_DICT) then
                TaskPlayAnim(ped, ANIM_DICT, ANIM_NAME, 8.0, -8.0, -1, 49, 0, false, false, false)
            end
        end)

        SetEnableHandcuffs(ped, true)
        DisablePlayerFiring(ped, true)
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        SetPedCanPlayGestureAnims(ped, false)
        DisplayRadar(false)
        AttachCuffProp(ped)

        local msg = mode == 'hard' and 'Du er sat i hårde håndjern.' or 'Du er blevet håndjernet.'
        lib.notify({ title = '🔒 Håndjern', description = msg, type = 'error', duration = 4000, position = 'center-right' })
        StartCuffLoop(mode)
    else
        cuffActive = false
        lib.notify({ title = '🔓 Håndjern', description = 'Håndjernene er fjernet.', type = 'success', duration = 4000, position = 'center-right' })
    end
end)

-- ── ESCORT EVENT ─────────────────────────────────────────────
RegisterNetEvent('mm_police:client:escort', function(copServerId, state)
    local ped    = cache.ped
    local copPed = GetPlayerPed(GetPlayerFromServerId(copServerId))
    if not DoesEntityExist(copPed) then return end

    MM.State.SetEscorted(state)
    LocalPlayer.state:set('isEscorted', state, false)

    if state then
        AttachEntityToEntity(ped, copPed, GetPedBoneIndex(copPed, 60309),
            0.54, 0.54, 0.0, 0.0, 0.0, 0.0,
            false, false, false, false, 2, true)
        lib.notify({ title = 'Eskort', description = 'Du bliver eskorteret.', type = 'inform', duration = 3000, position = 'center-right' })
    else
        if IsEntityAttached(ped) then DetachEntity(ped, true, false) end
        lib.notify({ title = 'Eskort', description = 'Eskorteringen er stoppet.', type = 'inform', duration = 3000, position = 'center-right' })
    end
end)

-- ── ESCORT DISCONNECT CHECK ───────────────────────────────────
-- FIX 6: adaptiv sleep — ikke altid Wait(2000)
CreateThread(function()
    while true do
        Wait(LocalPlayer.state.isEscorted and 500 or 2000)
        if LocalPlayer.state.isEscorted and IsEntityAttached(cache.ped) then
            local attached = GetEntityAttachedTo(cache.ped)
            if not DoesEntityExist(attached) or not IsEntityAPed(attached) then
                DetachEntity(cache.ped, true, false)
                MM.State.SetEscorted(false)
                LocalPlayer.state:set('isEscorted', false, false)
                lib.notify({ title = 'Eskort', description = 'Betjenten forsvandt — eskort stoppet.', type = 'error', duration = 4000, position = 'center-right' })
            end
        end
    end
end)

-- ── DEATH + RESOURCE STOP CLEANUP ────────────────────────────
AddEventHandler('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Cleanup()
end)