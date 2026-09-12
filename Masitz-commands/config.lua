-- ============================================================
--  Masitz-commands | config.lua
--  ESX Legacy · ox_lib · oxmysql
--
--  Standalone resource - rører IKKE eksisterende moderation/PVP
--  commands eller andre resources. Hver command har sin egen
--  config-sektion under Config.Command.<Navn>.
-- ============================================================

Config = Config or {}

Config.Debug = false

Config.Command = Config.Command or {}

-- ------------------------------------------------------------------
--  /pov [ID]  +  /povdone [ID]
-- ------------------------------------------------------------------
Config.Command.Pov = {
    Enabled = true,

    -- INGEN permission på selve /pov - alle spillere må bruge den.
    -- Cooldown er den eneste begrænsning, jf. kravspecifikationen.
    CooldownEnabled = true,
    Cooldown = 30, -- sekunder, håndhævet server-side pr. spiller der bruger /pov

    FirstTimeout = 15,  -- minutter til første frist
    SecondTimeout = 15, -- minutter ekstra efter en lib.alertDialog-advarsel (= 30 min total)
    RepeatTimeout = 20, -- minutter TOTAL hvis spilleren tidligere er blevet kicked for manglende POV

    -- Vist til spilleren og brugt i Discord-logs. Selve identifikationen af
    -- HVEM der har sendt POV sker aldrig ud fra denne tekst - kun ud fra
    -- den server-verificerede request (se DiscordApi herunder).
    DiscordChannelId = '1548295920079081472',
    DiscordChannelName = 'pov-indsendelse',

    KickReason = 'POV ikke indsendt inden for tidsfristen.',
    BanReason = 'Permanent udelukket: gentaget manglende POV-indsendelse.',

    -- /povdone kræver at man er staff. Samme mønster som resten af
    -- serverens admin-værktøjer (fx mm-adminpakke): ESX-gruppeliste, med
    -- mulighed for i stedet at bruge en ren ACE-permission.
    Povdone = {
        UseAcePermission = false,
        AcePermission = 'masitzcommands.povdone',
        AllowedGroups = { 'admin', 'superadmin', 'god', 'moderator' },
    },

    -- Automatisk POV-registrering fra en EKSTERN Discord-bot (uden for
    -- FiveM). Serveren eksponerer et lille, sikret HTTP-endpoint på selve
    -- FiveM-serverens almindelige port (samme mekanisme som fx txAdmin's
    -- egen API), som jeres bot kalder når en POV er blevet indsendt i
    -- Discord-kanalen. Se README.md for det fulde kontrakt-format.
    DiscordApi = {
        Enabled = true,
        HttpPath = '/masitz-commands/pov/complete',
        -- Skal matche X-Masitz-Secret-headeren i botens POST-request.
        -- ÆNDR denne værdi før brug - alle med den kan markere POV'er som
        -- modtaget, så den skal behandles som en adgangskode.
        SharedSecret = 'SÆT_EN_LANG_TILFÆLDIG_HEMMELIGHED_HER',
    },

    Webhook = 'DIN_WEBHOOK_HER',
}

-- ------------------------------------------------------------------
--  /check [ID]
-- ------------------------------------------------------------------
Config.Command.Check = {
    Enabled = true,

    -- /check henter IP, Steam-ID, Discord-ID osv. - skal derfor være
    -- begrænset til staff, ligesom /povdone.
    UseAcePermission = false,
    AcePermission = 'masitzcommands.check',
    AllowedGroups = { 'admin', 'superadmin', 'god', 'moderator' },

    -- Valgfri: sæt en Steam Web API-nøgle for at inkludere spillerens
    -- faktiske Steam-visningsnavn i embedet (ikke kun SteamID64 + link).
    -- Efterlades tom, vises "Ikke hentet (ingen API-nøgle)" i stedet -
    -- SteamID64 og profil-link virker altid uden nøgle.
    SteamApiKey = '',

    Webhook = 'DIN_WEBHOOK_HER',
}

-- ------------------------------------------------------------------
--  FÆLLES RATE LIMIT-BESKYTTELSE (misbrug af cooldown-omgåelse via
--  gentagne ugyldige kald) - pr. spiller, pr. command.
-- ------------------------------------------------------------------
Config.AbuseProtection = {
    MaxInvalidAttempts = 5,   -- ugyldige/kickede forsøg
    WindowSeconds = 30,       -- inden for dette tidsrum
}
