-- ============================================================
--  Masitz-mehandler | config.lua
--  ESX Legacy · ox_lib · ox_inventory
--
--  Alt herunder er trygt at ændre uden at røre Lua-koden.
-- ============================================================

Config = Config or {}
Config.MeHandler = {}

local M = Config.MeHandler

M.Enabled = true

-- Console-logs prefixet [Masitz-mehandler]. Ingen spam når false.
M.Debug = false

-- Standard-cooldown (ms) pr. handling. Kan overskrives pr. handling
-- via feltet "cooldown" i Config.MeHandler.Actions herunder.
M.Cooldown = 500

-- ============================================================
--  /ME-INTEGRATION
--  Scriptet skriver ALDRIG selv beskeder direkte i chatten. Det
--  udfører i stedet den kommando/det event din server allerede
--  bruger til /me, præcis som hvis spilleren selv havde skrevet den.
-- ============================================================
M.MeIntegration = {

    -- 'command' (anbefalet) -> udfører "/<Command> <besked>" via
    --            ExecuteCommand, PRÆCIS som hvis spilleren selv
    --            havde tastet det i chatten. Virker uanset om jeres
    --            /me er registreret client- eller server-side, da
    --            FiveM automatisk videresender ukendte client-kommandoer
    --            til serveren med spillerens rigtige identitet bevaret.
    --
    -- 'event'   -> trigger i stedet et lokalt klient-event med
    --              beskeden som argument (til chat-resources der
    --              forventer et event i stedet for en kommando).
    Mode = 'command',

    -- Bruges når Mode = 'command'.
    Command = 'me',

    -- Bruges når Mode = 'event'. Modtager (message: string).
    Event = nil,

    -- Hvis true, og INTET "/me"-command allerede er registreret af en
    -- anden ressource ved opstart, registrerer Masitz-mehandler selv en
    -- simpel fallback-udgave server-side (se server/server.lua).
    -- Overskriver ALDRIG et allerede eksisterende /me-system.
    RegisterFallback = true,
}

-- ============================================================
--  HANDLINGER (/me-beskeder)
--  Dette er den ENESTE tabel der definerer selve teksten og om en
--  handling er aktiv. Tilføj en ny handling ved blot at tilføje en
--  ny nøgle - intet andet skal ændres for at den kan bruges via
--  exports['Masitz-mehandler']:TriggerAction('dit_id').
-- ============================================================
M.Actions = {

    -- --- Bagagerum / handskerum (ox_inventory) ---
    trunk_open     = { enabled = true,  message = 'Åbner bagagerum' },
    trunk_close    = { enabled = true,  message = 'Lukker bagagerum' },
    glovebox_open  = { enabled = true,  message = 'Åbner handskerum' },
    glovebox_close = { enabled = true,  message = 'Lukker handskerum' },

    -- --- Bildør (ind-/udstigning) ---
    door_open      = { enabled = true,  message = 'Åbner bildør' },
    door_close     = { enabled = true,  message = 'Lukker bildør' },

    -- --- Motorhjelm (native dør-vinkel, se README - deaktiveret som
    --     standard, da dør-index for "motorhjelm" varierer mellem
    --     køretøjsmodeller og derfor kræver lidt tuning pr. server) ---
    hood_open      = { enabled = false, message = 'Åbner motorhjelm' },
    hood_close     = { enabled = false, message = 'Lukker motorhjelm' },

    -- --- Eksempler klar til fremtidig brug (deaktiveret som standard).
    --     Aktivér dem, og kald dem fra jeres egne scripts via:
    --     exports['Masitz-mehandler']:TriggerAction('radio_out') ---
    radio_out      = { enabled = false, message = 'Tager radioen frem' },
    radio_away     = { enabled = false, message = 'Lægger radioen væk' },
    phone_out      = { enabled = false, message = 'Tager telefonen frem' },
    phone_away     = { enabled = false, message = 'Lægger telefonen væk' },
    cuffs_out      = { enabled = false, message = 'Tager håndjern frem' },
    weapon_out     = { enabled = false, message = 'Tager sit våben frem' },
    weapon_away    = { enabled = false, message = 'Lægger sit våben væk' },
}

-- ============================================================
--  OX_INVENTORY-DETEKTION
--  Se README.md afsnit "Hvordan ox_inventory-integrationen fungerer"
--  for en fuld forklaring af hvordan dette virker UDEN at kende til
--  eller hooke noget specifikt keybind.
-- ============================================================
M.Inventory = {

    -- Hvor tæt (i meter) et køretøj skal være, for at et inventar der
    -- åbnes UDEN FOR et køretøj tolkes som et bagagerum. Matcher den
    -- radius ox_inventory selv bruger til trunk-adgang (~1.5m).
    TrunkProximity = 1.6,

    TrunkAction    = { open = 'trunk_open',    close = 'trunk_close' },
    GloveboxAction = { open = 'glovebox_open', close = 'glovebox_close' },
}

-- ============================================================
--  KØRETØJSDØRE (native GTA-dørindex, IKKE ox_inventory)
-- ============================================================
M.VehicleDoors = {

    -- Skal "Åbner/lukker bildør" kun trigges når spilleren selv er
    -- fører? (false = også som passager)
    OnlyDriver = false,

    DriverDoorAction = { open = 'door_open', close = 'door_close' },

    -- Ekstra døre der overvåges via dør-vinkel (kun aktiv hvis mindst
    -- én af de tilknyttede handlinger er enabled = true herover).
    -- Nøglen er GTA's dørindex. 4 = motorhjelm på langt de fleste
    -- almindelige køretøjer (nogle vare-/lastbiler og specialkøretøjer
    -- afviger - juster her ved behov).
    Watched = {
        [4] = { open = 'hood_open', close = 'hood_close' },
    },

    -- Interval (ms) for den lette dør-vinkel-poll, KUN mens spilleren
    -- rent faktisk står tæt på et køretøj der overvåges (se client.lua).
    PollInterval = 300,

    -- Interval (ms) for "er der overhovedet et køretøj i nærheden"-tjek
    -- mens spilleren IKKE står tæt på noget - holder pollingen billig.
    IdlePollInterval = 1500,
}
