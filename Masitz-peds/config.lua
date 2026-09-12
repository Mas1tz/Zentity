-- ============================================================
--  Masitz-peds | config.lua
--  ALT styres herfra. Tilføj/fjern/ret en ped ved kun at redigere
--  Config.Peds — ingen client/server-kode skal nogensinde ændres.
--
--  Dette er et shared_script (se fxmanifest.lua), så BÅDE client og
--  server ser præcis samme, allerede validerede data via
--  Config.Peds/Config.PedsById — valideringen nedenfor kører derfor
--  kun ét sted, ikke separat på hver side.
-- ============================================================

Config = Config or {}

Config.Debug = false

-- ============================================================
--  PED-DEFAULTS
--  Bruges når et felt er UDELADT i en ped-entry (ikke sat til false —
--  kun helt fraværende). Sæt et felt eksplicit til `false` for at
--  slå det fra pr. ped.
-- ============================================================
Config.Defaults = {
    freeze         = true,
    invincible     = true,
    block_events   = true,
    collision      = true,
    ragdoll        = false, -- statiske NPC'er skal normalt ikke kunne ragdolle
    canFlee        = false,
    canFight       = false,
    spawnDistance  = 50.0,
    despawnBuffer  = 20.0,  -- despawnDistance = spawnDistance + despawnBuffer, hvis despawnDistance ikke er sat
    targetDistance = 2.5,
    textUiDistance = 2.0,
    textUiPosition = 'right-center',
    modelTimeout   = 5000,  -- ms
    animTimeout    = 5000,  -- ms
    reportOnly     = false,
}

-- ============================================================
--  PEDS
--  Se README.md for en fuld feltreference. Kort opsummeret pr. entry:
--
--  id              (string, påkrævet, unik)             — bruges internt + i events/exports
--  model           (string, påkrævet)                    — ped-model
--  coords          (vec4, påkrævet)                       — x, y, z, heading
--  scenario        (string|nil)                            — TaskStartScenarioInPlace
--  animation       ({enabled, dict, anim, flag}|nil)        — bruges KUN hvis scenario er nil
--  freeze/invincible/block_events/collision/ragdoll (bool)  — se Config.Defaults
--  relationshipGroup (string|nil)
--  alpha           (number 0-255|nil)
--  visible         (bool|nil, default true)
--  spawnDistance/despawnDistance (number)                  — se "PED PLACERING/SPAWNING"
--  interaction     ('target'|'textui'|'both', default 'target')
--  target          ({enabled, distance, options = {...}})
--  textui          ({enabled, text, key, distance, position, icon, event/serverEvent/groups/canInteract})
--
--  target.options[n] / textui (samme "action"-form):
--    name        (string, kun target — id for optionen)
--    label       (string, kun target)
--    icon        (string, kun target — Font Awesome-klasse til ox_target)
--    distance    (number|nil — override af target.distance for denne ene option)
--    event       (string|nil)   — TriggerEvent client-side. Brug til IKKE-følsomme ting.
--    serverEvent (string|nil)   — sendes gennem den server-validerede gateway (se
--                                 server/main.lua). Brug ALTID denne til penge/items/adgang.
--    export      ({resource, method}|nil) — kalder et andet resources client-export
--                                 direkte (fx { resource = 'bach_duels', method =
--                                 'OpenDuelLobbyUi' }). Rent client-side ligesom `event`
--                                 — brug KUN til UI/menuer uden konsekvens, aldrig til
--                                 penge/items/adgang (bruger serverEvent til det).
--    groups      ({[jobName]=minGrade}|nil) — håndhæves BÅDE client-side (skjuler
--                                 optionen/prompten) OG server-side (hvis serverEvent bruges).
--    canInteract (function|nil) — ekstra, valgfri client-side gating ud over groups.
--
--  En option/textui skal have MINDST ét af event/serverEvent/export sat.
-- ============================================================

Config.Peds = {
    -- Eksempel 1: sikkerhedsvagt med en følsom handling (target + serverEvent + job-krav).
    -- Håndhæves BÅDE i ox_target's canInteract (skjuler optionen for ikke-politi) og
    -- server-side i Masitz-peds:server:interact, FØR den videresender til jeres eget
    -- lyttende resource-event (`police:server:openArmory`).
    {
        id     = 'security_guard_1',
        model  = 's_m_m_highsec_01',
        coords = vec4(123.45, 456.78, 32.10, 180.0),

        scenario     = 'WORLD_HUMAN_CLIPBOARD',
        freeze       = true,
        invincible   = true,
        block_events = true,

        spawnDistance = 60.0,

        interaction = 'target',
        target = {
            enabled  = true,
            distance = 2.5,
            options = {
                {
                    name  = 'talk',
                    label = 'Tal med vagten',
                    icon  = 'fa-solid fa-comments',
                    event = 'Masitz-peds:client:example',
                },
                {
                    name        = 'armory',
                    label       = 'Åbn våbenskab',
                    icon        = 'fa-solid fa-lock',
                    serverEvent = 'police:server:openArmory', -- lyttes af JERES eget politi-resource
                    groups      = { police = 0 },
                },
            },
        },
    },

    -- Eksempel 2: simpel informations-NPC, kun TextUI, ingen job-krav.
    {
        id     = 'info_npc_1',
        model  = 'a_m_m_business_01',
        coords = vec4(-50.2, 100.4, 68.5, 90.0),

        animation = {
            enabled = true,
            dict    = 'amb@world_human_hang_out_street@male_b@idle_a',
            anim    = 'idle_a',
            flag    = 1,
        },

        spawnDistance = 40.0,

        interaction = 'textui',
        textui = {
            enabled  = true,
            text     = '[E] Tal med person',
            key      = 'E',
            distance = 2.0,
            position = 'right-center',
            event    = 'Masitz-peds:client:example',
        },
    },

    -- Eksempel 3: begge interaktions-typer på samme ped.
    {
        id     = 'dealer_1',
        model  = 'g_m_y_mexgoon_01',
        coords = vec4(300.0, -200.0, 45.0, 270.0),

        freeze       = true,
        invincible   = true,
        block_events = true,
        relationshipGroup = 'CRIMINALS',

        spawnDistance   = 50.0,
        despawnDistance = 75.0,

        interaction = 'both',
        target = {
            enabled  = true,
            distance = 2.5,
            options = {
                {
                    name  = 'example',
                    label = 'Tal med person',
                    icon  = 'fa-solid fa-comments',
                    event = 'Masitz-peds:client:example',
                },
            },
        },
        textui = {
            enabled  = true,
            text     = '[E] Tal med dealer',
            key      = 'E',
            distance = 2.0,
            position = 'right-center',
            event    = 'Masitz-peds:client:example',
        },
    },

    -- Eksempel 4: åbner et ANDET resources UI direkte via dets export
    -- (her bach_duels' duel-lobby) i stedet for et event — ingen
    -- mellemliggende event-handler nødvendig for rene UI-kald.
    {
        id     = 'dealer_2',
        model  = 'mp_m_shopkeep_01',
        coords = vec4(885.60, -11.18, 78.76, 332.12),

        freeze       = true,
        invincible   = true,
        block_events = true,
        relationshipGroup = 'CRIMINALS',

        spawnDistance   = 50.0,
        despawnDistance = 75.0,

        interaction = 'target',
        target = {
            enabled  = true,
            distance = 2.5,
            options = {
                {
                    name   = 'open_duels',
                    label  = 'Åbn Duels',
                    icon   = 'fa-solid fa-gun',
                    export = { resource = 'bach_duels', method = 'OpenDuelLobbyUi' },
                },
            },
        },
    },
}

-- ============================================================
--  INTERN — validering + indeksering. Deles af client og server.
--  Rør ikke ved dette medmindre du udvider selve config-skemaet.
-- ============================================================

local function LogConfigError(fmt, ...)
    print(('^1[Masitz-peds] ' .. fmt .. '^7'):format(...))
end

local function ValidateActionLike(cfg, label)
    if not cfg.event and not cfg.serverEvent and not cfg.export then
        LogConfigError('%s har hverken "event", "serverEvent" eller "export" — den kan aldrig gøre noget.', label)
        return false
    end
    if cfg.export then
        if type(cfg.export) ~= 'table' or type(cfg.export.resource) ~= 'string' or cfg.export.resource == ''
            or type(cfg.export.method) ~= 'string' or cfg.export.method == '' then
            LogConfigError('%s.export skal være { resource = "...", method = "..." }.', label)
            return false
        end
    end
    if cfg.groups and type(cfg.groups) ~= 'table' then
        LogConfigError('%s.groups skal være en tabel ({ jobnavn = mingrad }).', label)
        return false
    end
    return true
end

local function IsValidPedConfig(cfg, index)
    if type(cfg) ~= 'table' then
        LogConfigError('Config.Peds[%d] er ikke en gyldig tabel.', index)
        return false
    end
    if type(cfg.id) ~= 'string' or cfg.id == '' then
        LogConfigError('Config.Peds[%d] mangler et gyldigt id.', index)
        return false
    end
    if type(cfg.model) ~= 'string' or cfg.model == '' then
        LogConfigError('[%s] mangler en gyldig model.', cfg.id)
        return false
    end
    if type(cfg.coords) ~= 'vector4' then
        LogConfigError('[%s] coords skal være en vec4(x, y, z, heading).', cfg.id)
        return false
    end

    local interaction = cfg.interaction or 'target'
    if interaction ~= 'target' and interaction ~= 'textui' and interaction ~= 'both' then
        LogConfigError('[%s] ugyldig interaction-type: "%s" (skal være target/textui/both).', cfg.id, tostring(interaction))
        return false
    end

    local usesTarget = interaction == 'target' or interaction == 'both'
    local usesTextUi = interaction == 'textui' or interaction == 'both'

    if usesTarget then
        if not cfg.target or not cfg.target.enabled then
            LogConfigError('[%s] interaction inkluderer "target", men target.enabled er ikke sat.', cfg.id)
            return false
        end
        if type(cfg.target.options) ~= 'table' or #cfg.target.options == 0 then
            LogConfigError('[%s] target.enabled er sat, men target.options er tom.', cfg.id)
            return false
        end
        for i, opt in ipairs(cfg.target.options) do
            if type(opt.name) ~= 'string' or opt.name == '' or type(opt.label) ~= 'string' or opt.label == '' then
                LogConfigError('[%s] target.options[%d] mangler name/label.', cfg.id, i)
                return false
            end
            if not ValidateActionLike(opt, ('[%s] target.options[%d] (%s)'):format(cfg.id, i, opt.name)) then
                return false
            end
        end
    end

    if usesTextUi then
        if not cfg.textui or not cfg.textui.enabled then
            LogConfigError('[%s] interaction inkluderer "textui", men textui.enabled er ikke sat.', cfg.id)
            return false
        end
        if type(cfg.textui.text) ~= 'string' or cfg.textui.text == '' then
            LogConfigError('[%s] textui.enabled er sat, men textui.text mangler.', cfg.id)
            return false
        end
        if not ValidateActionLike(cfg.textui, ('[%s] textui'):format(cfg.id)) then
            return false
        end
    end

    if cfg.animation and cfg.animation.enabled then
        if type(cfg.animation.dict) ~= 'string' or type(cfg.animation.anim) ~= 'string' then
            LogConfigError('[%s] animation.enabled er sat, men dict/anim mangler.', cfg.id)
            return false
        end
    end

    return true
end

Config.PedsById = {}

local function BuildValidatedPedList()
    local out, seenIds = {}, {}

    for index, cfg in ipairs(Config.Peds) do
        if IsValidPedConfig(cfg, index) then
            if seenIds[cfg.id] then
                LogConfigError('Duplikeret ped-id fundet og sprunget over: "%s".', cfg.id)
            else
                seenIds[cfg.id] = true

                local d = Config.Defaults
                cfg.interaction = cfg.interaction or 'target'
                if cfg.freeze == nil then cfg.freeze = d.freeze end
                if cfg.invincible == nil then cfg.invincible = d.invincible end
                if cfg.block_events == nil then cfg.block_events = d.block_events end
                if cfg.collision == nil then cfg.collision = d.collision end
                if cfg.ragdoll == nil then cfg.ragdoll = d.ragdoll end
                if cfg.canFlee == nil then cfg.canFlee = d.canFlee end
                if cfg.canFight == nil then cfg.canFight = d.canFight end
                if cfg.visible == nil then cfg.visible = true end

                cfg.spawnDistance = cfg.spawnDistance or cfg.distance or d.spawnDistance
                cfg.despawnDistance = cfg.despawnDistance or (cfg.spawnDistance + d.despawnBuffer)
                cfg.spawnDistanceSq = cfg.spawnDistance * cfg.spawnDistance
                cfg.despawnDistanceSq = cfg.despawnDistance * cfg.despawnDistance

                if cfg.target and cfg.target.enabled then
                    cfg.target.distance = cfg.target.distance or d.targetDistance
                end
                if cfg.textui and cfg.textui.enabled then
                    cfg.textui.distance = cfg.textui.distance or d.textUiDistance
                    cfg.textui.distanceSq = cfg.textui.distance * cfg.textui.distance
                    cfg.textui.position = cfg.textui.position or d.textUiPosition
                    cfg.textui.key = cfg.textui.key or 'E'
                end

                out[#out + 1] = cfg
                Config.PedsById[cfg.id] = cfg
            end
        end
    end

    return out
end

Config.Peds = BuildValidatedPedList()
