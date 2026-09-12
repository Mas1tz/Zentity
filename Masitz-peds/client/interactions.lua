-- ============================================================
--  Masitz-peds | client/interactions.lua
--  ox_target-registrering, TextUI, job/gruppe-gating, og selve
--  interaktions-afsendelsen (event/serverEvent).
-- ============================================================

PEDS = PEDS or {}

local function DebugPrint(fmt, ...)
    if Config.Debug then
        print(('[Masitz-peds] ' .. fmt):format(...))
    end
end

-- ─── ESX JOB-CACHE ───────────────────────────────────────────────
-- Selvafsluttende bootstrap-loop (kører KUN indtil spillerdata er
-- klar ved login/resource-start) + event-opdateret derefter. Ingen
-- permanent loop, ingen gentagne ESX-kald i canInteract-tjek.
local ESX = exports['es_extended']:getSharedObject()
local PlayerJob = { name = 'unemployed', grade = 0 }

-- Selvafsluttende: polling stopper i det øjeblik jobdata er klar ved
-- login/resource-start, og holdes derefter opdateret udelukkende via
-- esx:setJob/esx:playerLoaded — ikke et permanent loop.
CreateThread(function()
    while not ESX.GetPlayerData().job do
        Wait(200)
    end
    PlayerJob = ESX.GetPlayerData().job
end)

RegisterNetEvent('esx:setJob', function(job)
    PlayerJob = job
end)

RegisterNetEvent('esx:playerLoaded', function(xPlayer)
    if xPlayer and xPlayer.job then
        PlayerJob = xPlayer.job
    end
end)

-- ─── GRUPPE/JOB + CUSTOM CANINTERACT ─────────────────────────────
-- Bruges til BÅDE target-options og textui — begge deler samme
-- "action"-form (event/serverEvent/groups/canInteract).
local function PassesGroups(groups)
    if not groups then return true end
    local requiredGrade = groups[PlayerJob.name]
    if requiredGrade == nil then return false end
    return (PlayerJob.grade or 0) >= requiredGrade
end

function PEDS.EvaluateCanInteract(action, entity, distance, coords, name, bone)
    if not PassesGroups(action.groups) then
        return false
    end
    if action.canInteract then
        local ok = action.canInteract(entity, distance, coords, name, bone)
        if not ok then return false end
    end
    return true
end

-- ─── INTERAKTIONS-AFSENDELSE ──────────────────────────────────────
-- Følsomme handlinger (serverEvent) sendes KUN som ped-id + option-
-- navn — serveren slår selv den rigtige config-entry op og
-- genvaliderer job/afstand, uanset hvad klienten påstår.
function PEDS.TriggerAction(action, id, optionName)
    if action.event then
        TriggerEvent(action.event, id, optionName)
    end
    if action.serverEvent then
        TriggerServerEvent('Masitz-peds:server:interact', id, optionName)
    end
    DebugPrint('Interaction triggered: ped=%s option=%s', id, tostring(optionName))
end

-- ─── OX_TARGET ────────────────────────────────────────────────────
local function BuildTargetOptions(cfg, id)
    local options = {}
    for i, opt in ipairs(cfg.target.options) do
        options[i] = {
            name = ('masitz_peds_%s_%s'):format(id, opt.name),
            label = opt.label,
            icon = opt.icon,
            distance = opt.distance or cfg.target.distance,
            canInteract = function(entity, distance, coords, name, bone)
                return PEDS.EvaluateCanInteract(opt, entity, distance, coords, name, bone)
            end,
            onSelect = function()
                PEDS.TriggerAction(opt, id, opt.name)
            end,
        }
    end
    return options
end

function PEDS.RegisterPedTarget(id)
    local state = PEDS.Runtime[id]
    local cfg = state and state.config
    if not cfg or not cfg.target or not cfg.target.enabled then return end
    if not state.entity or not DoesEntityExist(state.entity) then return end

    exports.ox_target:addLocalEntity(state.entity, BuildTargetOptions(cfg, id))
    state.targetRegistered = true
    DebugPrint('Target registered: %s', id)
end

function PEDS.UnregisterPedTarget(id)
    local state = PEDS.Runtime[id]
    if not state or not state.targetRegistered then return end

    if state.entity and DoesEntityExist(state.entity) then
        exports.ox_target:removeLocalEntity(state.entity)
    end
    state.targetRegistered = false
    DebugPrint('Target unregistered: %s', id)
end

-- ─── TEXTUI ────────────────────────────────────────────────────────
-- ox_lib's TextUI er ÉN global overlay (ikke pr. entity) — vi
-- tracker derfor kun ÉT "i øjeblikket vist" ped-id ad gangen i stedet
-- for en pr.-ped boolean, så de aldrig kan komme ud af sync.
PEDS.CurrentTextUiPedId = nil

local KEY_CONTROLS = {
    E = 38,
    F = 23,
}

function PEDS.GetTextUiControl(cfg)
    local control = KEY_CONTROLS[cfg.textui.key]
    if not control then
        DebugPrint('Ukendt textui.key "%s" for %s — falder tilbage til E.', tostring(cfg.textui.key), cfg.id)
        control = KEY_CONTROLS.E
    end
    return control
end

function PEDS.ShowTextUi(id)
    if PEDS.CurrentTextUiPedId == id then return end

    local cfg = PEDS.Runtime[id].config
    lib.showTextUI(cfg.textui.text, {
        position = cfg.textui.position,
        icon = cfg.textui.icon,
    })
    PEDS.CurrentTextUiPedId = id
end

function PEDS.HideTextUi()
    if not PEDS.CurrentTextUiPedId then return end
    lib.hideTextUI()
    PEDS.CurrentTextUiPedId = nil
end

function PEDS.HideTextUiIfActive(id)
    if PEDS.CurrentTextUiPedId == id then
        PEDS.HideTextUi()
    end
end
