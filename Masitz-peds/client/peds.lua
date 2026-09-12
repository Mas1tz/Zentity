-- ============================================================
--  Masitz-peds | client/peds.lua
--  Ped-livscyklus: model/animations-loading, spawn, despawn,
--  native ped-opsætning. Ingen af disse funktioner starter noget
--  loop selv — det styres udelukkende af client/main.lua's ene
--  distance-loop.
-- ============================================================

PEDS = PEDS or {}
PEDS.Runtime = PEDS.Runtime or {} -- [id] = { config, entity, spawned, pending }

local function DebugPrint(fmt, ...)
    if Config.Debug then
        print(('[Masitz-peds] ' .. fmt):format(...))
    end
end

local function LogError(fmt, ...)
    print(('^1[Masitz-peds] ' .. fmt .. '^7'):format(...))
end

-- ─── RUNTIME-INITIALISERING ───────────────────────────────────────
function PEDS.InitRuntime()
    for id, cfg in pairs(Config.PedsById) do
        PEDS.Runtime[id] = {
            config = cfg,
            entity = nil,
            spawned = false,
            pending = false,
            modelHash = joaat(cfg.model),
        }
    end
end

-- ─── MODEL / ANIMATION LOADING (bounded, crasher aldrig) ──────────
local function RequestModelWithTimeout(hash, timeoutMs)
    if not IsModelValid(hash) then
        return false
    end
    if HasModelLoaded(hash) then
        return true
    end

    RequestModel(hash)
    local start = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - start > timeoutMs then
            return false
        end
        Wait(0)
    end
    return true
end

local function RequestAnimDictWithTimeout(dict, timeoutMs)
    if not DoesAnimDictExist(dict) then
        return false
    end
    if HasAnimDictLoaded(dict) then
        return true
    end

    RequestAnimDict(dict)
    local start = GetGameTimer()
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() - start > timeoutMs then
            return false
        end
        Wait(0)
    end
    return true
end

local function PlayConfiguredAnimation(ped, animCfg)
    if not RequestAnimDictWithTimeout(animCfg.dict, Config.Defaults.animTimeout) then
        LogError('Kunne ikke loade animation dict "%s" — pedet står bare stille.', animCfg.dict)
        return
    end

    TaskPlayAnim(ped, animCfg.dict, animCfg.anim, 8.0, -8.0, -1, animCfg.flag or 1, 0, false, false, false)
    RemoveAnimDict(animCfg.dict)
end

-- ─── NATIV PED-OPSÆTNING ud fra config ────────────────────────────
local function ApplyPedSettings(ped, cfg)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, cfg.block_events)
    SetPedFleeAttributes(ped, 0, cfg.canFlee)
    SetPedCombatAttributes(ped, 46, not cfg.canFight) -- BF_CanFightArmedPedsWhenNotArmed, inverteret som "vil ikke kæmpe"
    SetPedCanRagdoll(ped, cfg.ragdoll)
    FreezeEntityPosition(ped, cfg.freeze)
    SetEntityInvincible(ped, cfg.invincible)

    if not cfg.collision then
        SetEntityCollision(ped, false, false)
    end
    if cfg.relationshipGroup then
        SetPedRelationshipGroupHash(ped, GetHashKey(cfg.relationshipGroup))
    end
    if cfg.alpha then
        SetEntityAlpha(ped, cfg.alpha, false)
    end
    if not cfg.visible then
        SetEntityVisible(ped, false, false)
    end

    if cfg.scenario then
        TaskStartScenarioInPlace(ped, cfg.scenario, 0, true)
    elseif cfg.animation and cfg.animation.enabled then
        PlayConfiguredAnimation(ped, cfg.animation)
    end
end

-- ─── SPAWN (asynkron — blokerer ALDRIG hoved-loopet mens en model
--     loader) ──────────────────────────────────────────────────────
function PEDS.CreateConfiguredPed(id)
    local state = PEDS.Runtime[id]
    if not state or state.spawned or state.pending then return end
    state.pending = true

    CreateThread(function()
        local cfg = state.config

        if not RequestModelWithTimeout(state.modelHash, Config.Defaults.modelTimeout) then
            LogError('Kunne ikke loade model for ped "%s" (%s) — springer over.', id, cfg.model)
            state.pending = false
            return
        end

        -- Annulleret imens modellen loadede (fx despawn/resource stop)?
        if not state.pending then return end

        local c = cfg.coords
        local ped = CreatePed(4, state.modelHash, c.x, c.y, c.z - 1.0, c.w or 0.0, false, true)
        SetModelAsNoLongerNeeded(state.modelHash)

        if not DoesEntityExist(ped) then
            LogError('CreatePed fejlede for "%s".', id)
            state.pending = false
            return
        end

        ApplyPedSettings(ped, cfg)

        state.entity = ped
        state.spawned = true
        state.pending = false

        if cfg.target and cfg.target.enabled then
            PEDS.RegisterPedTarget(id)
        end

        DebugPrint('Ped spawned: %s', id)
    end)
end

-- ─── FULD OPRYDNING for ÉN ped (bruges af despawn OG resource stop) ─
function PEDS.CleanupPed(id)
    local state = PEDS.Runtime[id]
    if not state then return end

    state.pending = false -- afbryder en evt. igangværende async spawn

    if state.entity and DoesEntityExist(state.entity) then
        PEDS.UnregisterPedTarget(id)
        PEDS.HideTextUiIfActive(id)
        SetEntityAsMissionEntity(state.entity, false, true)
        DeletePed(state.entity)
    end

    state.entity = nil
    state.spawned = false
end

function PEDS.DeleteConfiguredPed(id)
    local state = PEDS.Runtime[id]
    if not state or (not state.spawned and not state.pending) then return end

    PEDS.CleanupPed(id)
    DebugPrint('Ped despawned: %s', id)
end

-- ─── LÆSE-ADGANG (klar til senere exports, ingen omskrivning nødvendig) ─
function PEDS.GetPed(id)
    local state = PEDS.Runtime[id]
    return state and state.entity or nil
end

function PEDS.GetAllPeds()
    local out = {}
    for id, state in pairs(PEDS.Runtime) do
        if state.spawned then
            out[id] = state.entity
        end
    end
    return out
end
