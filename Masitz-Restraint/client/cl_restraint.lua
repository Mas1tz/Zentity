-- ============================================================
--  Masitz-Restraint | client/cl_restraint.lua
--  UI/animations/lokal spejling af server-state.
--
--  VIGTIGT: `localState` er en SPEJLING af serverens state, ALDRIG en
--  autoritet i sig selv. Den må KUN ændres via `syncState`-handleren
--  nedenfor, som udelukkende kommer fra serveren. Alt der ligner en
--  sikkerhedsbeslutning her på klienten er kun til UX (fx om en
--  ox_target-mulighed skal vises) - den reelle validering sker altid
--  server-side i sv_restraint.lua.
-- ============================================================

local C = Config.Restraint

local localState = {
    restrained = false,
    restraintType = nil,
    isDead = false,
    carriedBy = nil,
    carrying = nil,
    draggedBy = nil,
    dragging = nil,
}

-- Cache af andre spilleres senest kendte (offentlige) state, til UX-brug
-- som fx ox_target-options ("er personen allerede restrained?").
local knownStates = {}

local currentCarryTarget = nil
local isDragged = false
local draggerServerId = nil
local currentDragTarget = nil

local restraintLoopActive = false
local deathPollActive = false

local function DebugPrint(fmt, ...)
    if not C.Debug then return end
    print(('[Masitz-Restraint] ' .. fmt):format(...))
end

-- ------------------------------------------------------------------
--  HJÆLPEFUNKTIONER (UX-only, ALDRIG sikkerhedsafgørende)
-- ------------------------------------------------------------------

local function IsPedDead()
    local ped = PlayerPedId()
    return IsEntityDead(ped) or GetEntityHealth(ped) <= 0
end

local function GetClosestPlayer(maxDist)
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local closest, closestDist = -1, maxDist

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local targetPed = GetPlayerPed(playerId)
            if targetPed and targetPed ~= 0 then
                local dist = #(myCoords - GetEntityCoords(targetPed))
                if dist <= closestDist then
                    closest = playerId
                    closestDist = dist
                end
            end
        end
    end
    return closest
end

-- ------------------------------------------------------------------
--  RESTRAINT-LOOP (animation + control-lock)
--  Starter/stopper KUN mens man reelt er restrained - ingen evig
--  Wait(0)-loop.
-- ------------------------------------------------------------------

local function StartRestraintLoop()
    if restraintLoopActive then return end
    restraintLoopActive = true

    CreateThread(function()
        while localState.restrained and restraintLoopActive do
            local typeCfg = Config.Restraints[localState.restraintType]

            -- Undlader tvungen animation mens man bliver båret/trukket, eller er død -
            -- ellers konflikter animationerne (samme klasse fix begge veje).
            if typeCfg and not localState.carriedBy and not localState.draggedBy and not IsPedDead() then
                local dict = typeCfg.animDict
                if dict then
                    if lib.requestAnimDict(dict, 2000) then
                        local ped = PlayerPedId()
                        if not IsEntityPlayingAnim(ped, dict, typeCfg.animName, 3) then
                            TaskPlayAnim(ped, dict, typeCfg.animName, 8.0, 8.0, -1, typeCfg.animFlag or 49, 0, false, false, false)
                        end
                    end
                end

                if typeCfg.blockedControls then
                    for _, control in ipairs(typeCfg.blockedControls) do
                        DisableControlAction(0, control, true)
                    end
                end
            end

            Wait(0)
        end
        restraintLoopActive = false
    end)
end

local function StopRestraintLoop()
    restraintLoopActive = false
end

-- ------------------------------------------------------------------
--  DØDS-DETEKTION (best-effort, event-drevet + fallback-poll)
--  Bevidst ikke bundet til ét bestemt dødsscript - vi lytter på de
--  mest almindelige ESX/baseevents-hooks, og et resource der har sit
--  eget setup kan i stedet kalde exports.SetPlayerDeathState server-side.
-- ------------------------------------------------------------------

local function ReportDeath(isDead)
    TriggerServerEvent('masitz_restraint:server:reportDeath', isDead)
end

AddEventHandler('esx:onPlayerDeath', function() ReportDeath(true) end)
AddEventHandler('baseevents:onPlayerDied', function() ReportDeath(true) end)
AddEventHandler('baseevents:onPlayerKilled', function() ReportDeath(true) end)
AddEventHandler('esx:onPlayerSpawn', function() ReportDeath(false) end)
AddEventHandler('playerSpawned', function() ReportDeath(false) end)
AddEventHandler('baseevents:onPlayerRevived', function() ReportDeath(false) end)

-- Fallback: poller kun mens restrained, så vi opdager død selv hvis
-- serverens/scriptets dødshooks ikke matcher (custom dødssystem uden
-- SetPlayerDeathState-integration).
local function StartDeathPoll()
    if deathPollActive then return end
    deathPollActive = true

    CreateThread(function()
        local lastKnown = IsPedDead()
        while localState.restrained and deathPollActive do
            Wait(1500)
            local nowDead = IsPedDead()
            if nowDead ~= lastKnown then
                lastKnown = nowDead
                ReportDeath(nowDead)
            end
        end
        deathPollActive = false
    end)
end

local function StopDeathPoll()
    deathPollActive = false
end

-- ------------------------------------------------------------------
--  CARRY (den bårne part)
-- ------------------------------------------------------------------

local function StartEStopWatcher(target)
    CreateThread(function()
        while currentCarryTarget == target do
            if IsControlJustReleased(0, 38) then -- E
                TriggerServerEvent('masitz_restraint:server:stopCarry')
                break
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('masitz_restraint:client:carryStarted', function(target)
    currentCarryTarget = target
    StartEStopWatcher(target)
end)

RegisterNetEvent('masitz_restraint:client:carryTarget', function(carrierServerId)
    local carrierPlayerId = GetPlayerFromServerId(carrierServerId)
    if carrierPlayerId == -1 then return end

    local ped = PlayerPedId()
    local carrierPed = GetPlayerPed(carrierPlayerId)

    ClearPedTasks(ped)
    local anim = Config.CarryAnim.target
    if lib.requestAnimDict(anim.dict, 2000) then
        AttachEntityToEntity(ped, carrierPed, GetPedBoneIndex(carrierPed, 11816), anim.x, anim.y, anim.z, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
        TaskPlayAnim(ped, anim.dict, anim.anim, 3.0, 3.0, -1, anim.flag or 33, 0, false, false, false)
    end
end)

-- ------------------------------------------------------------------
--  DRAG (den trukne part)
-- ------------------------------------------------------------------

local function StartDragFollowThread()
    CreateThread(function()
        while isDragged and draggerServerId do
            Wait(0)
        end
    end)
end

RegisterNetEvent('masitz_restraint:client:dragStarted', function(target)
    currentDragTarget = target
end)

RegisterNetEvent('masitz_restraint:client:dragTarget', function(draggerSrv)
    local draggerPlayerId = GetPlayerFromServerId(draggerSrv)
    if draggerPlayerId == -1 then return end

    isDragged = true
    draggerServerId = draggerSrv

    local ped = PlayerPedId()
    local draggerPed = GetPlayerPed(draggerPlayerId)

    ClearPedTasks(ped)
    AttachEntityToEntity(ped, draggerPed, GetPedBoneIndex(draggerPed, Config.DragAttachBone), Config.DragOffset.x, Config.DragOffset.y, Config.DragOffset.z, 0.0, 0.0, 0.0, true, true, false, true, 1, true)

    StartDragFollowThread()
end)

-- ------------------------------------------------------------------
--  FÆLLES STOP (carry og drag), sendt fra serveren til BEGGE parter
-- ------------------------------------------------------------------

RegisterNetEvent('masitz_restraint:client:stopCarryDrag', function()
    local ped = PlayerPedId()

    if currentCarryTarget then
        currentCarryTarget = nil
    end

    if currentDragTarget then
        currentDragTarget = nil
    end

    if isDragged then
        isDragged = false
        draggerServerId = nil
        DetachEntity(ped, true, true)
        ClearPedTasks(ped)
    end

    -- Hvis vi selv var den der bar/trak nogen, og de var attachet til os,
    -- er der intet at detache på vores egen ped - men ryd evt. egne tasks.
    if not localState.restrained then
        ClearPedTasksImmediately(ped)
    end
end)

-- ------------------------------------------------------------------
--  STATE-SYNC - eneste sted `localState` må ændres
-- ------------------------------------------------------------------

RegisterNetEvent('masitz_restraint:client:syncState', function(newState)
    if type(newState) ~= 'table' then return end

    local wasRestrained = localState.restrained

    localState.restrained    = newState.restrained or false
    localState.restraintType = newState.restraintType
    localState.isDead        = newState.isDead or false
    localState.carriedBy     = newState.carriedBy
    localState.carrying      = newState.carrying
    localState.draggedBy     = newState.draggedBy
    localState.dragging      = newState.dragging

    local ok = pcall(function()
        LocalPlayer.state:set('invBusy', localState.restrained, true)
    end)
    if not ok then DebugPrint('Kunne ikke sætte invBusy state.') end

    if localState.restrained and not wasRestrained then
        local notice = (Config.Text and Config.Text.restrainedNotice) or 'Dine hænder er bundet!'
        lib.notify({ title = 'Masitz-Restraint', description = notice, type = 'error' })
        StartRestraintLoop()
        StartDeathPoll()
        DebugPrint('[SYNC] restrained=true type=%s', tostring(localState.restraintType))
    elseif (not localState.restrained) and wasRestrained then
        StopRestraintLoop()
        StopDeathPoll()
        ClearPedTasks(PlayerPedId())
        DebugPrint('[SYNC] restrained=false')
    end
end)

RegisterNetEvent('masitz_restraint:client:notify', function(text, type)
    lib.notify({ title = 'Masitz-Restraint', description = text, type = type or 'inform' })
end)

-- ------------------------------------------------------------------
--  BRUG-ITEM -> ÅBN RESTRAINT-MENU
--  Toggle: hvis target allerede er restrained, prøv unrestrain i
--  stedet. Matcher original scriptets adfærd (ToggleZiptie).
-- ------------------------------------------------------------------

RegisterNetEvent('masitz_restraint:client:openRestraintMenu', function(restraintType)
    local target = GetClosestPlayer(C.MaxApplyDistance)
    if target == -1 then
        lib.notify({ description = Config.Text.noOneNearby, type = 'error' })
        return
    end

    local targetSrc = GetPlayerServerId(target)
    local isTargetRestrained = lib.callback.await('masitz_restraint:server:isRestrained', false, targetSrc)

    if isTargetRestrained then
        TriggerServerEvent('masitz_restraint:server:requestUnrestrain', targetSrc)
    else
        TriggerServerEvent('masitz_restraint:server:requestRestrain', targetSrc, restraintType)
    end
end)

-- ------------------------------------------------------------------
--  OFFENTLIGE BROADCAST-EVENTS (til UX-cache, ikke sikkerhed)
-- ------------------------------------------------------------------

RegisterNetEvent('masitz-restraint:client:stateChanged', function(target, restrained, restraintType)
    knownStates[target] = knownStates[target] or {}
    knownStates[target].restrained = restrained
    knownStates[target].restraintType = restraintType
end)

RegisterNetEvent('masitz-restraint:client:deathStateChanged', function(target, isDead)
    knownStates[target] = knownStates[target] or {}
    knownStates[target].isDead = isDead
end)

-- ------------------------------------------------------------------
--  RESSOURCE-LIVSCYKLUS
-- ------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    StopRestraintLoop()
    StopDeathPoll()
    local ped = PlayerPedId()
    pcall(function() ClearPedTasks(ped) end)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    -- Server-siden force-resync'er alle spillere kort efter start, så vi
    -- behøver ikke selv bede om state her.
end)

-- ============================================================
--  EXPORTS (client)
-- ============================================================

exports('IsRestrained', function()
    return localState.restrained
end)

exports('GetRestraintType', function()
    return localState.restraintType
end)

exports('GetRestraintState', function()
    return {
        restrained = localState.restrained,
        restraintType = localState.restraintType,
        isDead = localState.isDead,
        carriedBy = localState.carriedBy,
        carrying = localState.carrying,
        draggedBy = localState.draggedBy,
        dragging = localState.dragging,
    }
end)

exports('GetKnownRestraintState', function(serverId)
    return knownStates[serverId]
end)

exports('RequestRestrain', function(targetServerId, restraintType)
    TriggerServerEvent('masitz_restraint:server:requestRestrain', targetServerId, restraintType)
end)

exports('RequestUnrestrain', function(targetServerId)
    TriggerServerEvent('masitz_restraint:server:requestUnrestrain', targetServerId)
end)

exports('RequestCarry', function(targetServerId)
    TriggerServerEvent('masitz_restraint:server:requestCarry', targetServerId)
end)

exports('RequestDrag', function(targetServerId)
    TriggerServerEvent('masitz_restraint:server:requestDrag', targetServerId)
end)

-- ------------------------------------------------------------------
--  LEGACY-KOMPATIBLE EXPORTS/EVENTS
--  Bevarer de oprindelige navne/signaturer så eksisterende integrationer
--  (radial-menu, keybinds osv.) fortsætter med at virke uændret.
-- ------------------------------------------------------------------

exports('ToggleZiptie', function()
    local target = GetClosestPlayer(C.MaxApplyDistance)
    if target == -1 then
        lib.notify({ description = Config.Text.noOneNearby, type = 'error' })
        return
    end
    local targetSrc = GetPlayerServerId(target)
    local isTargetRestrained = lib.callback.await('masitz_restraint:server:isRestrained', false, targetSrc)
    if isTargetRestrained then
        TriggerServerEvent('masitz_restraint:server:requestUnrestrain', targetSrc)
    else
        TriggerServerEvent('masitz_restraint:server:requestRestrain', targetSrc, C.DefaultRestraintType)
    end
end)

exports('ToggleCarry', function()
    if currentCarryTarget then
        TriggerServerEvent('masitz_restraint:server:stopCarry')
        return
    end
    local target = GetClosestPlayer(C.MaxCarryDistance)
    if target == -1 then
        lib.notify({ description = Config.Text.noOneNearby, type = 'error' })
        return
    end
    TriggerServerEvent('masitz_restraint:server:requestCarry', GetPlayerServerId(target))
end)

exports('ToggleEscort', function()
    if currentDragTarget then
        TriggerServerEvent('masitz_restraint:server:stopDrag')
        return
    end
    local target = GetClosestPlayer(C.MaxDragDistance)
    if target == -1 then
        lib.notify({ description = Config.Text.noOneNearby, type = 'error' })
        return
    end
    TriggerServerEvent('masitz_restraint:server:requestDrag', GetPlayerServerId(target))
end)

-- Kompatibilitets-shim for det oprindelige mm_system-event.
RegisterNetEvent('mm_system:ziptieMenu', function()
    exports[GetCurrentResourceName()]:ToggleZiptie()
end)
