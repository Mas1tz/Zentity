-- ============================================================
--  Masitz-Restraint | config.lua
--  ESX Legacy · ox_lib · ox_inventory
--
--  Alt herunder er trygt at ændre uden at røre Lua-koden.
-- ============================================================

Config = Config or {}

Config.Restraint = {

    Enabled = true,

    -- Console-logs prefixet [Masitz-Restraint]. Ingen spam når false.
    Debug = false,

    -- ------------------------------------------------------------------
    -- AFSTAND (server-beregnet — ALDRIG klient-input, se sv_restraint.lua)
    -- ------------------------------------------------------------------
    MaxApplyDistance  = 3.0,  -- hvor tæt man skal være for at lægge en restraint på nogen
    MaxRemoveDistance = 3.0,  -- hvor tæt man skal være for at fjerne en restraint fra nogen
    MaxCarryDistance  = 3.0,  -- hvor tæt man skal være for at tage nogen op
    MaxDragDistance   = 5.0,  -- lidt mere lempeligt, da drag er en løbende handling

    -- ------------------------------------------------------------------
    -- REGLER
    -- ------------------------------------------------------------------

    -- Må en spiller selv vælge sig selv som target? (næsten aldrig ønsket)
    AllowSelfApply  = false,
    AllowSelfRemove = false,

    -- Hvem må fjerne en restraint igen?
    --   'any'             -> enhver spiller inden for MaxRemoveDistance (matcher original opførsel)
    --   'restrainer_only' -> kun den der selv lagde den på
    --   'job'             -> kun spillere hvis ESX-job findes i UnrestrainJobs herunder
    UnrestrainPermission = 'any',
    UnrestrainJobs = {
        ['police']  = true,
        ['sheriff'] = true,
    },

    -- Skal carry/drag kræve at target reelt er restrained?
    -- (matcher original: drag krævede det, carry gjorde ikke)
    RequireRestraintForDrag  = true,
    RequireRestraintForCarry = false,

    -- Hvad sker der ved død?
    ClearRestraintOnDeath   = false, -- håndjern falder ikke bare af fordi man dør
    StopCarryDragOnDeath    = true,  -- men man bliver sat ned/sluppet, så animationen ikke låser fast

    -- Anti-spam: minimum tid (ms) mellem to restraint-relaterede handlinger fra samme spiller
    ActionCooldownMs = 1200,

    -- Standard restraint-type når intet andet er angivet (fx legacy ToggleZiptie-export)
    DefaultRestraintType = 'ziptie',

    -- ------------------------------------------------------------------
    -- VALGFRI EKSTERN CHAT/BESKED-INTEGRATION
    -- Original brugte en hardcoded 'TriggerServerEvent(\'3dme:executeMe\', msg)'.
    -- Det er bevaret, men nu valgfrit og config-styret i stedet for hardcoded
    -- ind i handlingerne selv.
    -- ------------------------------------------------------------------
    ChatIntegration = {
        Enabled = true,
        Event   = '3dme:executeMe',
    },
}

-- ============================================================
--  RESTRAINT TYPES
--  Tilføj en ny type ved blot at tilføje en ny nøgle herunder —
--  intet andet skal ændres.
--
--  Felter:
--    label               -> visningsnavn
--    item                -> ox_inventory item krævet, eller nil for intet item
--    requireItemToApply  -> skal item bruges for at lægge den på?
--    requireItemToRemove -> skal item bruges for at tage den af?
--    giveItemBackOnRemove-> få item tilbage når den tages af?
--    animDict/animName/animFlag -> tvungen "restrained idle" animation
--    blockedControls     -> liste af control-actions der disables mens restrained
--    canBeCarried/Dragged-> kan denne type bruges sammen med carry/drag?
-- ============================================================
Config.Restraints = {

    ziptie = {
        label = 'Strips',
        item = 'ziptie',
        requireItemToApply   = true,
        requireItemToRemove  = false,
        giveItemBackOnRemove = false,

        animDict = 'mp_arresting',
        animName = 'idle',
        animFlag = 49,

        blockedControls = {
            19,  -- L-ALT (ox_target)
            24,  -- Attack
            25,  -- Aim
            37,  -- Weapon Wheel
            140, -- Melee
            289, -- F2 (Inventory)
            170, -- F3 (Menuer)
            167, -- F6 (Job menuer)
            21,  -- Sprint
            22,  -- Hop
        },

        canBeCarried = true,
        canBeDragged = true,
    },

    -- Eksempel på en ekstra type — udkommentér og tilpas frit:
    -- handcuffs = {
    --     label = 'Håndjern',
    --     item = 'handcuffs',
    --     requireItemToApply   = true,
    --     requireItemToRemove  = false,
    --     giveItemBackOnRemove = false,
    --     animDict = 'mp_arresting',
    --     animName = 'idle',
    --     animFlag = 49,
    --     blockedControls = {
    --         19, 24, 25, 37, 140, 289, 170, 167, 21, 22,
    --     },
    --     canBeCarried = true,
    --     canBeDragged = true,
    -- },
}

-- ============================================================
--  CARRY / DRAG — animationer og attach-punkter
-- ============================================================
Config.CarryAnim = {
    carrier = { dict = 'missfinale_c2mcs_1', anim = 'fin_c2_mcs_1_camman', flag = 49 },
    target  = { dict = 'nm', anim = 'firemans_carry', flag = 33, x = 0.27, y = 0.15, z = 0.63 },
}

Config.DragAttachBone = 11816 -- Pelvis
Config.DragOffset = { x = 0.54, y = 0.54, z = 0.0 }

-- ============================================================
--  TEKSTER (dansk, samlet ét sted — ingen hardcoded strenge i koden)
-- ============================================================
Config.Text = {
    noOneNearby         = 'Ingen i nærheden',
    noItem               = 'Du har ikke det nødvendige item på dig!',
    applied               = 'Du brugte %s på personen.',
    removed               = 'Du fjernede %s.',
    restrainedNotice      = 'Dine hænder er bundet!',
    dragRequiresRestraint = 'Personen skal være bundet for at blive eskorteret!',
    cannotCarry           = 'Personen kan ikke løftes lige nu',
    releasingTarget        = 'Slipper personen',
    liftingTarget           = 'Løfter personen',
    escortingTarget         = 'Eskorterer personen',
    noPermission           = 'Du har ikke tilladelse til det.',
    tooFarAway             = 'Du er for langt væk.',
    alreadyRestrained      = 'Personen er allerede bundet.',
    notRestrained          = 'Personen er ikke bundet.',
    actionTooFast          = 'Vent lidt før du prøver igen.',
    inVehicle              = 'Det kan ikke bruges mens nogen sidder i et køretøj.',
}
