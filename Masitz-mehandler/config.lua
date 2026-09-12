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

    -- --- Eksempler klar til fremtidig brug (deaktiveret som standard).
    --     Aktivér dem, og kald dem fra jeres egne scripts via:
    --     exports['Masitz-mehandler']:TriggerAction('phone_out') ---
    phone_out      = { enabled = false, message = 'Tager telefonen frem' },
    phone_away     = { enabled = false, message = 'Lægger telefonen væk' },
    cuffs_out      = { enabled = false, message = 'Tager håndjern frem' },
    weapon_out     = { enabled = false, message = 'Tager sit våben frem' },
    weapon_away    = { enabled = false, message = 'Lægger sit våben væk' },

    -- --- Restraint/anholdelses-handlinger (kaldes fra Masitz-Restraint
    --     via exports['Masitz-mehandler']:TriggerAction('<id>')) ---
    saet_i_strips            = { enabled = true, message = 'Sætter personen i strips' },
    tag_ud_af_strips         = { enabled = true, message = 'Tager personen ud af strips' },
    saet_person_i_koretoj    = { enabled = true, message = 'Sætter personen i køretøjet' },
    tag_person_ud_af_koretoj = { enabled = true, message = 'Tager personen ud af køretøjet' },
    leder_efter              = { enabled = true, message = 'Leder efter ting i personens lommer' },
    eskortere_personen       = { enabled = true, message = 'Eskorterer personen' },
    loefter_person           = { enabled = true, message = 'Løfter personen' },
    slipper_personen         = { enabled = true, message = 'Slipper personen' },
    saetter_i_koretoj        = { enabled = true, message = 'Sætter personen ind i køretøjet' },
    visitere_personen        = { enabled = true, message = 'Visiterer personen' },
    tager_fra_koretoj        = { enabled = true, message = 'Tager personen ud af køretøjet' },
    bagagerum                = { enabled = true, message = 'Åbner bagagerum' },
    handskerum               = { enabled = true, message = 'Åbner handskerum' },
    blindfold                = { enabled = true, message = 'Giver blindfold på' },
    blindfold_off            = { enabled = true, message = 'Tager blindfold af' },
    overgiv                  = { enabled = true, message = '~y~Overgiver sig' },
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
