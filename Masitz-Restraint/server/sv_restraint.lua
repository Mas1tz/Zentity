-- ============================================================
--  Masitz-Restraint | server/sv_restraint.lua
--  Server-authoritative restraint / carry / drag system.
--
--  ALT sikkerhedskritisk state ligger her og KUN her. Klienten
--  får aldrig lov at fortælle serveren "jeg er ikke længere
--  restrained" og få det til at ske - klienten kan kun BEDE om
--  en handling, serveren validerer og bestemmer.
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

local C = Config.Restraint

-- ------------------------------------------------------------------
--  STATE
--  states[source] = {
--      restrained    = bool,
--      restraintType = string|nil,
--      restrainedBy  = number|nil,   -- server id på den der lagde den på (nil hvis system)
--      restrainedAt  = os.time()|nil,
--      isDead        = bool,
--      carrying      = number|nil,   -- server id på den DENNE spiller bærer
--      carriedBy     = number|nil,   -- server id på den der bærer DENNE spiller
--      dragging      = number|nil,   -- server id på den DENNE spiller trækker
--      draggedBy     = number|nil,   -- server id på den der trækker DENNE spiller
--  }
-- ------------------------------------------------------------------
local states = {}

local function DebugPrint(fmt, ...)
    if not C.Debug then return end
    print(('[Masitz-Restraint] ' .. fmt):format(...))
end

local function GetOrCreateState(src)
    if not states[src] then
        states[src] = {
            restrained = false,
            restraintType = nil,
            restrainedBy = nil,
            restrainedAt = nil,
            isDead = false,
            carrying = nil,
            carriedBy = nil,
            dragging = nil,
            draggedBy = nil,
        }
    end
    return states[src]
end

-- Sikker "public" snapshot - aldrig returnér den rå tabel til andre
-- ressourcer/klienter, så intern state ikke kan mutéres udefra.
local function GetPublicState(src)
    local s = states[src]
    if not s then
        return {
            restrained = false, restraintType = nil, isDead = false,
            carrying = nil, carriedBy = nil, dragging = nil, draggedBy = nil,
        }
    end
    return {
        restrained    = s.restrained,
        restraintType = s.restraintType,
        isDead        = s.isDead,
        carrying      = s.carrying,
        carriedBy     = s.carriedBy,
        dragging      = s.dragging,
        draggedBy     = s.draggedBy,
    }
end

local function IsValidPlayer(src)
    if type(src) ~= 'number' then return false end
    return GetPlayerName(src) ~= nil
end

-- ------------------------------------------------------------------
--  ANTI-SPAM
-- ------------------------------------------------------------------
local LastAction = {}

local function CheckCooldown(src)
    local now = GetGameTimer()
    local last = LastAction[src]
    if last and (now - last) < C.ActionCooldownMs then
        return false
    end
    LastAction[src] = now
    return true
end

-- ------------------------------------------------------------------
--  AFSTAND - ALTID beregnet server-side ud fra native ped-koordinater.
--  Klient-sendte koordinater bruges ALDRIG til sikkerhedsbeslutninger.
-- ------------------------------------------------------------------
local function GetPedCoordsSafe(src)
    local ok, ped = pcall(GetPlayerPed, src)
    if not ok or not ped or ped == 0 then return nil end
    local ok2, coords = pcall(GetEntityCoords, ped)
    if not ok2 or not coords then return nil end
    return coords
end

-- Fail-closed: kan vi ikke læse koordinater, er handlingen IKKE tilladt.
local function IsWithinDistance(srcA, srcB, maxDist)
    local a = GetPedCoordsSafe(srcA)
    local b = GetPedCoordsSafe(srcB)
    if not a or not b then return false end
    return #(a - b) <= maxDist
end

-- Restrain/carry/drag giver ingen mening (og er direkte farligt - se
-- README "Kendte sikkerhedsrettelser") mens en af parterne sidder i et
-- køretøj: ClearPedTasks() på en siddende ped tvinger dem ud af sædet,
-- hvilket ellers kan bruges til at "smide" en fører ud af sin egen bil
-- og overtage sædet. Fail-closed: kan vi ikke læse ped/vehicle-state,
-- antager vi at spilleren SIDDER i et køretøj (blokerer handlingen).
local function IsInVehicle(src)
    local ok, ped = pcall(GetPlayerPed, src)
    if not ok or not ped or ped == 0 then return true end
    local ok2, vehicle = pcall(GetVehiclePedIsIn, ped, false)
    if not ok2 then return true end
    return vehicle ~= 0
end

-- ------------------------------------------------------------------
--  OX_INVENTORY WRAPPERS - altid pcall'et, altid fail-closed
-- ------------------------------------------------------------------
local function GetItemCount(src, item)
    if not item then return math.huge end -- intet item krævet
    local ok, count = pcall(function()
        return exports.ox_inventory:GetItemCount(src, item)
    end)
    if not ok or type(count) ~= 'number' then return 0 end
    return count
end

local function RemoveItem(src, item, count)
    if not item then return true end
    local ok, result = pcall(function()
        return exports.ox_inventory:RemoveItem(src, item, count or 1)
    end)
    return ok and result and true or false
end

local function AddItem(src, item, count)
    if not item then return true end
    local ok, result = pcall(function()
        return exports.ox_inventory:AddItem(src, item, count or 1)
    end)
    return ok and result and true or false
end

-- ------------------------------------------------------------------
--  SYNC TIL KLIENT
-- ------------------------------------------------------------------
local function SyncStateToClient(src)
    if not IsValidPlayer(src) then return end
    TriggerClientEvent('masitz_restraint:client:syncState', src, GetPublicState(src))
end

-- ------------------------------------------------------------------
--  OFFENTLIGE NOTIFIKATIONS-EVENTS
--  Disse er IKKE en sikkerhedsautoritet - andre ressourcer må lytte
--  til dem for at reagere på ændringer (fx UI/HUD), men skal ALDRIG
--  bruge dem som grundlag for egne sikkerhedsbeslutninger. Brug altid
--  exports (IsRestrained osv.) eller callbacks til det.
-- ------------------------------------------------------------------
local function NotifyStateChanged(target, restrained, restraintType, byPlayer)
    TriggerEvent('masitz-restraint:server:stateChanged', target, restrained, restraintType, byPlayer)
    TriggerClientEvent('masitz-restraint:client:stateChanged', -1, target, restrained, restraintType)
end

local function NotifyDeathStateChanged(target, isDead)
    TriggerEvent('masitz-restraint:server:deathStateChanged', target, isDead)
    TriggerClientEvent('masitz-restraint:client:deathStateChanged', -1, target, isDead)
end

local function FireChatIntegration(src, msg)
    local cfg = C.ChatIntegration
    if not cfg or not cfg.Enabled or not cfg.Event then return end
    local ok = pcall(function()
        TriggerServerEvent(cfg.Event, msg)
    end)
    if not ok then DebugPrint('Chat-integration event fejlede (event findes muligvis ikke): %s', cfg.Event) end
end

-- ------------------------------------------------------------------
--  FEJLBESKEDER
-- ------------------------------------------------------------------
local REASON_TEXT = {
    no_target            = Config.Text.noOneNearby,
    no_item              = Config.Text.noItem,
    no_permission        = Config.Text.noPermission,
    too_far               = Config.Text.tooFarAway,
    already_restrained   = Config.Text.alreadyRestrained,
    not_restrained       = Config.Text.notRestrained,
    too_fast              = Config.Text.actionTooFast,
    invalid_type         = 'Ugyldig restraint-type.',
    self_target          = 'Du kan ikke bruge det her på dig selv.',
    unknown              = 'Der skete en fejl.',
    cannot_carry          = Config.Text.cannotCarry,
    drag_requires_restraint = Config.Text.dragRequiresRestraint,
    busy                  = 'Personen er optaget lige nu.',
    in_vehicle            = Config.Text.inVehicle,
}

local function NotifyActionFailed(src, reason)
    if not IsValidPlayer(src) then return end
    local text = REASON_TEXT[reason] or REASON_TEXT.unknown
    TriggerClientEvent('masitz_restraint:client:notify', src, text, 'error')
end

local function NotifySuccess(src, text)
    if not IsValidPlayer(src) then return end
    TriggerClientEvent('masitz_restraint:client:notify', src, text, 'success')
end

-- ------------------------------------------------------------------
--  RACE-CONDITION GUARD
--  Bruges kun omkring handlinger der reelt yielder (ox_inventory-kald),
--  da events i FiveM's Lua-scheduler kører atomisk imellem yield-points.
--  Carry/drag start/stop har ingen yield-points og er derfor allerede
--  atomiske i sig selv.
-- ------------------------------------------------------------------
local Pending = {}

-- ------------------------------------------------------------------
--  CARRY
-- ------------------------------------------------------------------

-- Stopper target's egen aktive carry, hvor target er den BÆRENDE part (actor).
function StopCarryInternal(actorSrc)
    local aState = states[actorSrc]
    if not aState or not aState.carrying then return end
    local target = aState.carrying
    local tState = states[target]
    aState.carrying = nil
    if tState then tState.carriedBy = nil end
    if IsValidPlayer(actorSrc) then
        TriggerClientEvent('masitz_restraint:client:stopCarryDrag', actorSrc)
    end
    if IsValidPlayer(target) then
        TriggerClientEvent('masitz_restraint:client:stopCarryDrag', target)
    end
end

local function DoStopCarry(initiator)
    local iState = states[initiator]
    if not iState or not iState.carrying then return false, 'not_restrained' end
    StopCarryInternal(initiator)
    NotifySuccess(initiator, Config.Text.releasingTarget)
    return true
end

-- ------------------------------------------------------------------
--  DRAG
-- ------------------------------------------------------------------

-- Stopper en drag-relation ud fra target's synspunkt (uanset hvem der kalder).
function StopDragInternal(target)
    local tState = states[target]
    if not tState or not tState.draggedBy then return end
    local dragger = tState.draggedBy
    local dState = states[dragger]
    tState.draggedBy = nil
    if dState then dState.dragging = nil end
    if IsValidPlayer(dragger) then
        TriggerClientEvent('masitz_restraint:client:stopCarryDrag', dragger)
    end
    if IsValidPlayer(target) then
        TriggerClientEvent('masitz_restraint:client:stopCarryDrag', target)
    end
end

local function DoStopDrag(initiator)
    local iState = states[initiator]
    if not iState or not iState.dragging then return false, 'not_restrained' end
    local target = iState.dragging
    StopDragInternal(target)
    NotifySuccess(initiator, Config.Text.releasingTarget)
    return true
end

local function DoStartCarry(initiator, target)
    if not IsValidPlayer(initiator) or not IsValidPlayer(target) then return false, 'no_target' end
    if initiator == target then return false, 'self_target' end
    if not CheckCooldown(initiator) then return false, 'too_fast' end

    local iState = GetOrCreateState(initiator)
    local tState = GetOrCreateState(target)

    if iState.isDead or tState.isDead then return false, 'cannot_carry' end
    if iState.restrained then return false, 'cannot_carry' end -- bundne hænder kan ikke bære
    if iState.carrying or iState.dragging then return false, 'busy' end
    if tState.carriedBy or tState.draggedBy or tState.carrying or tState.dragging then return false, 'busy' end

    -- Ingen af parterne må sidde i et køretøj (se IsInVehicle) - ellers kan
    -- carry bruges til at rive en fører/passager ud af deres eget sæde.
    if IsInVehicle(initiator) or IsInVehicle(target) then return false, 'in_vehicle' end

    local rtype = tState.restraintType and Config.Restraints[tState.restraintType] or nil
    if C.RequireRestraintForCarry and not tState.restrained then
        return false, 'not_restrained'
    end
    if tState.restrained and rtype and rtype.canBeCarried == false then
        return false, 'cannot_carry'
    end

    if not IsWithinDistance(initiator, target, C.MaxCarryDistance) then
        return false, 'too_far'
    end

    -- Ingen yield-points herunder -> atomisk i forhold til andre event-kald.
    iState.carrying = target
    tState.carriedBy = initiator
    TriggerClientEvent('masitz_restraint:client:carryTarget', target, initiator)
    TriggerClientEvent('masitz_restraint:client:carryStarted', initiator, target)
    NotifySuccess(initiator, Config.Text.liftingTarget)
    FireChatIntegration(initiator, Config.Text.liftingTarget)
    return true
end

local function DoStartDrag(initiator, target)
    if not IsValidPlayer(initiator) or not IsValidPlayer(target) then return false, 'no_target' end
    if initiator == target then return false, 'self_target' end
    if not CheckCooldown(initiator) then return false, 'too_fast' end

    local iState = GetOrCreateState(initiator)
    local tState = GetOrCreateState(target)

    if iState.isDead then return false, 'cannot_carry' end
    if iState.restrained then return false, 'cannot_carry' end
    if iState.carrying or iState.dragging then return false, 'busy' end
    if tState.carriedBy or tState.draggedBy or tState.carrying or tState.dragging then return false, 'busy' end

    -- Se DoStartCarry - samme begrundelse: ingen af parterne må sidde i
    -- et køretøj.
    if IsInVehicle(initiator) or IsInVehicle(target) then return false, 'in_vehicle' end

    if C.RequireRestraintForDrag and not tState.restrained then
        return false, 'drag_requires_restraint'
    end

    local rtype = tState.restraintType and Config.Restraints[tState.restraintType] or nil
    if rtype and rtype.canBeDragged == false then
        return false, 'cannot_carry'
    end

    if not IsWithinDistance(initiator, target, C.MaxDragDistance) then
        return false, 'too_far'
    end

    iState.dragging = target
    tState.draggedBy = initiator
    TriggerClientEvent('masitz_restraint:client:dragTarget', target, initiator)
    TriggerClientEvent('masitz_restraint:client:dragStarted', initiator, target)
    NotifySuccess(initiator, Config.Text.escortingTarget)
    FireChatIntegration(initiator, Config.Text.escortingTarget)
    return true
end

-- ------------------------------------------------------------------
--  RESTRAIN / UNRESTRAIN
-- ------------------------------------------------------------------

local function HasUnrestrainPermission(initiator, target, restrainedBy)
    if C.UnrestrainPermission == 'restrainer_only' then
        return restrainedBy ~= nil and restrainedBy == initiator
    elseif C.UnrestrainPermission == 'job' then
        local xPlayer = ESX.GetPlayerFromId(initiator)
        if not xPlayer then return false end
        local job = xPlayer.getJob and xPlayer.getJob() or nil
        return job ~= nil and C.UnrestrainJobs[job.name] == true
    end
    return true -- 'any'
end

local function DoRestrain(initiator, target, restraintType, isSystem)
    if not IsValidPlayer(target) then return false, 'no_target' end
    if not isSystem then
        if not IsValidPlayer(initiator) then return false, 'no_target' end
        if not C.AllowSelfApply and initiator == target then return false, 'self_target' end
        if not CheckCooldown(initiator) then return false, 'too_fast' end
    end

    restraintType = restraintType or C.DefaultRestraintType
    local typeCfg = Config.Restraints[restraintType]
    if not typeCfg then return false, 'invalid_type' end

    if Pending[target] then return false, 'busy' end

    local tState = GetOrCreateState(target)
    if tState.restrained then return false, 'already_restrained' end

    -- Giver ikke fysisk mening (og spiller dårligt sammen med den tvungne
    -- restrained-animation) at lægge en restraint på nogen mens de sidder
    -- i et køretøj - gælder også system-/export-kald.
    if IsInVehicle(target) then return false, 'in_vehicle' end

    if not isSystem then
        if not IsWithinDistance(initiator, target, C.MaxApplyDistance) then
            return false, 'too_far'
        end
        if typeCfg.requireItemToApply then
            if GetItemCount(initiator, typeCfg.item) < 1 then
                return false, 'no_item'
            end
        end
    end

    Pending[target] = true
    local ok, err = pcall(function()
        if not isSystem and typeCfg.requireItemToApply then
            local removed = RemoveItem(initiator, typeCfg.item, 1)
            if not removed then error('item_remove_failed') end
        end

        -- Billig invariant-tjek: rent teoretisk beskyttelse hvis fremtidig
        -- kode tilføjer et yield-point herover - lige nu er dette IKKE en
        -- reel race, da Pending[target] allerede udelukker det.
        local state = GetOrCreateState(target)
        if state.restrained then error('already_restrained') end

        state.restrained    = true
        state.restraintType = restraintType
        state.restrainedBy  = isSystem and nil or initiator
        state.restrainedAt  = os.time()

        -- Man kan ikke aktivt bære/trække en anden mens ens egne hænder lige
        -- er blevet bundet - stop target's EGEN aktive carry/drag som ACTOR
        -- (ikke hvis target selv bliver båret/trukket, det er stadig fint).
        if state.carrying then StopCarryInternal(target) end
        if state.dragging then StopDragInternal(state.dragging) end

        SyncStateToClient(target)
        NotifyStateChanged(target, true, restraintType, isSystem and nil or initiator)

        if not isSystem then
            NotifySuccess(initiator, Config.Text.applied:format(typeCfg.label))
            FireChatIntegration(initiator, Config.Text.applied:format(typeCfg.label))
        end
    end)
    Pending[target] = nil

    if not ok then
        DebugPrint('DoRestrain fejlede for target %s: %s', tostring(target), tostring(err))
        return false, 'unknown'
    end
    return true
end

local function DoUnrestrain(initiator, target, isSystem)
    if not IsValidPlayer(target) then return false, 'no_target' end
    if not isSystem then
        if not IsValidPlayer(initiator) then return false, 'no_target' end
        if not C.AllowSelfRemove and initiator == target then return false, 'self_target' end
        if not CheckCooldown(initiator) then return false, 'too_fast' end
    end

    if Pending[target] then return false, 'busy' end

    local state = states[target]
    if not state or not state.restrained then return false, 'not_restrained' end

    if not isSystem then
        if not IsWithinDistance(initiator, target, C.MaxRemoveDistance) then
            return false, 'too_far'
        end
        if not HasUnrestrainPermission(initiator, target, state.restrainedBy) then
            return false, 'no_permission'
        end
    end

    local typeCfg = Config.Restraints[state.restraintType]

    Pending[target] = true
    local ok, err = pcall(function()
        if not isSystem and typeCfg then
            if typeCfg.requireItemToRemove then
                if GetItemCount(initiator, typeCfg.item) < 1 then error('no_item') end
                RemoveItem(initiator, typeCfg.item, 1)
            end
            if typeCfg.giveItemBackOnRemove then
                AddItem(target, typeCfg.item, 1)
            end
        end

        local restraintTypeForMsg = state.restraintType
        state.restrained    = false
        state.restraintType = nil
        state.restrainedBy  = nil
        state.restrainedAt  = nil

        -- Drag kræver restraint - fjernes den, stoppes en igangværende drag.
        if C.RequireRestraintForDrag and state.draggedBy then
            StopDragInternal(target)
        end

        SyncStateToClient(target)
        NotifyStateChanged(target, false, nil, isSystem and nil or initiator)

        if not isSystem then
            local label = (Config.Restraints[restraintTypeForMsg] or {}).label or 'restraint'
            NotifySuccess(initiator, Config.Text.removed:format(label))
            FireChatIntegration(initiator, Config.Text.removed:format(label))
        end
    end)
    Pending[target] = nil

    if not ok then
        local reason = tostring(err):find('no_item') and 'no_item' or 'unknown'
        if reason == 'unknown' then
            DebugPrint('DoUnrestrain fejlede for target %s: %s', tostring(target), tostring(err))
        end
        return false, reason
    end
    return true
end

-- ------------------------------------------------------------------
--  DØD / GENOPLIVELSE
--  Bevidst IKKE bundet til ét specifikt dødsscript - death-state
--  sættes enten via klientens best-effort selv-rapportering eller
--  via det autoritative SetPlayerDeathState-export fra andre ressourcer.
-- ------------------------------------------------------------------
local function HandleDeathStateChange(src, isDead)
    if not IsValidPlayer(src) then return end
    local state = GetOrCreateState(src)
    if state.isDead == isDead then return end
    state.isDead = isDead

    if isDead then
        if C.StopCarryDragOnDeath then
            if state.carrying then StopCarryInternal(src) end
            if state.draggedBy then StopDragInternal(src) end
            if state.carriedBy then
                local carrierState = states[state.carriedBy]
                if carrierState and carrierState.carrying == src then
                    StopCarryInternal(state.carriedBy)
                end
            end
            if state.dragging then
                StopDragInternal(state.dragging)
            end
        end
        if C.ClearRestraintOnDeath and state.restrained then
            state.restrained = false
            state.restraintType = nil
            state.restrainedBy = nil
            state.restrainedAt = nil
        end
    end

    SyncStateToClient(src)
    NotifyDeathStateChanged(src, isDead)
end

-- ============================================================
--  NET EVENTS (klient -> server)
--  Alle validerer selv target/afstand/item/permission - klienten
--  kan aldrig "bede sig fri" ved bare at sende sit eget id.
-- ============================================================

RegisterNetEvent('masitz_restraint:server:requestRestrain', function(target, restraintType)
    local src = source
    if type(target) ~= 'number' then return end
    local ok, reason = DoRestrain(src, target, restraintType, false)
    if not ok then NotifyActionFailed(src, reason) end
end)

RegisterNetEvent('masitz_restraint:server:requestUnrestrain', function(target)
    local src = source
    if type(target) ~= 'number' then return end
    local ok, reason = DoUnrestrain(src, target, false)
    if not ok then NotifyActionFailed(src, reason) end
end)

RegisterNetEvent('masitz_restraint:server:requestCarry', function(target)
    local src = source
    if type(target) ~= 'number' then return end
    local ok, reason = DoStartCarry(src, target)
    if not ok then NotifyActionFailed(src, reason) end
end)

RegisterNetEvent('masitz_restraint:server:stopCarry', function()
    local src = source
    local ok, reason = DoStopCarry(src)
    if not ok then NotifyActionFailed(src, reason) end
end)

RegisterNetEvent('masitz_restraint:server:requestDrag', function(target)
    local src = source
    if type(target) ~= 'number' then return end
    local ok, reason = DoStartDrag(src, target)
    if not ok then NotifyActionFailed(src, reason) end
end)

RegisterNetEvent('masitz_restraint:server:stopDrag', function()
    local src = source
    local ok, reason = DoStopDrag(src)
    if not ok then NotifyActionFailed(src, reason) end
end)

-- Best-effort selv-rapportering fra klienten (fx ESX/baseevents-hooks).
-- Bruges KUN til isDead-tracking, aldrig til restraint-sikkerhed.
RegisterNetEvent('masitz_restraint:server:reportDeath', function(isDead)
    local src = source
    if type(isDead) ~= 'boolean' then return end
    HandleDeathStateChange(src, isDead)
end)

-- ============================================================
--  CALLBACKS (ox_lib)
-- ============================================================

lib.callback.register('masitz_restraint:server:isRestrained', function(_, target)
    if type(target) ~= 'number' then return false end
    local s = states[target]
    return s ~= nil and s.restrained or false
end)

lib.callback.register('masitz_restraint:server:getRestraintState', function(_, target)
    if type(target) ~= 'number' then return GetPublicState(-1) end
    return GetPublicState(target)
end)

lib.callback.register('masitz_restraint:server:canCarry', function(src, target)
    if type(target) ~= 'number' then return false end
    local iState = states[src]
    local tState = states[target]
    if not iState or not tState then return true end
    if iState.restrained or iState.carrying or iState.dragging then return false end
    if tState.carriedBy or tState.draggedBy then return false end
    return true
end)

-- ============================================================
--  EXPORTS (server) - dokumenteret fuldt i README.md
-- ============================================================

exports('IsRestrained', function(target)
    local s = states[target]
    return s ~= nil and s.restrained or false
end)

exports('GetRestraintType', function(target)
    local s = states[target]
    return s and s.restraintType or nil
end)

exports('GetRestraintState', function(target)
    return GetPublicState(target)
end)

exports('IsPlayerDead', function(target)
    local s = states[target]
    return s ~= nil and s.isDead or false
end)

-- Autoritativt API til andre ressourcer/admin-kommandoer. Går uden om
-- afstand/item/cooldown-tjek (systemet er selv autoriteten her), men
-- respekterer stadig at man ikke kan dobbelt-restraine osv.
exports('RestrainPlayer', function(target, restraintType)
    return DoRestrain(nil, target, restraintType, true)
end)

exports('UnrestrainPlayer', function(target)
    return DoUnrestrain(nil, target, true)
end)

-- Autoritativt hook til jeres eget/eksterne død-/genoplivningssystem.
-- Kald denne fra jeres medic-/dødsscript i stedet for at binde jer til
-- ét bestemt tredjeparts-script.
exports('SetPlayerDeathState', function(target, isDead)
    if type(target) ~= 'number' or type(isDead) ~= 'boolean' then return false end
    HandleDeathStateChange(target, isDead)
    return true
end)

-- ============================================================
--  OPRYDNING
-- ============================================================

AddEventHandler('playerDropped', function()
    local src = source
    local state = states[src]
    if state then
        -- Ryd op i BEGGE retninger af enhver relation, ikke kun dem
        -- src selv startede.
        if state.carrying then StopCarryInternal(src) end
        if state.dragging then StopDragInternal(state.dragging) end
        if state.carriedBy then
            local carrierState = states[state.carriedBy]
            if carrierState and carrierState.carrying == src then
                StopCarryInternal(state.carriedBy)
            end
        end
        if state.draggedBy then
            StopDragInternal(src)
        end
    end
    states[src] = nil
    LastAction[src] = nil
    Pending[src] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    -- Server-state persisteres bevidst ikke (se README "Known limitations"),
    -- så der er intet at gemme her - men vi resync'er klienter ved (gen)start.
end)

-- Ved (gen)start af ressourcen har alle spillere en frisk/tom klient-side
-- state fra scratch. Force-resync alle for at undgå desync efter en
-- resource-restart hvor gamle klienter kunne have en forældet lokal kopi.
CreateThread(function()
    Wait(1000)
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if src then
            GetOrCreateState(src)
            SyncStateToClient(src)
        end
    end
    DebugPrint('Resource startet - alle tilsluttede spillere er blevet resynkroniseret.')
end)

-- ============================================================
--  AUTOMATISK ITEM-REGISTRERING (brug-item -> åbn restraint-menu)
--  Registrerer kun items der reelt er defineret i Config.Restraints,
--  så vi ikke kræver at item'et findes hvis ressourcen bruges uden
--  det (fx kun via export/target).
-- ============================================================
CreateThread(function()
    for restraintType, cfg in pairs(Config.Restraints) do
        if cfg.item then
            local itemName = cfg.item
            local rType = restraintType
            ESX.RegisterUsableItem(itemName, function(src)
                TriggerClientEvent('masitz_restraint:client:openRestraintMenu', src, rType)
            end)
        end
    end
end)
