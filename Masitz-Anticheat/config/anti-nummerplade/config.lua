--[[
    ============================================================================
    Masitz-Anticheat — anti-nummerplade — config.lua
    ============================================================================

    Alt herunder er trygt at ændre. Intet i client.lua/server.lua bør skulle
    røres for normal drift/tuning.

    HUSK: Config-værdier her er kun "policy" (hvor aggressivt systemet skal
    reagere). De er IKKE en sikkerhedsgrænse i sig selv — selve sikkerheden
    (ownership-verifikation, item-check, duplicate-check osv.) sker altid
    server-side i server.lua uanset hvad der står her.
]]

Config = Config or {}

Config.AntiNummerplade = {

    -- ------------------------------------------------------------------
    -- GENERELT
    -- ------------------------------------------------------------------

    -- Slår hele anti-nummerplade modulet til/fra.
    Enabled = true,

    -- Debug-print i server- og client-konsollen. Skal være false i produktion.
    -- Når true: logger hvert tjek/beslutning. Når false: kun WARNING/DETECTION/BAN/ERROR.
    Debug = false,

    -- ------------------------------------------------------------------
    -- BAN SYSTEM
    -- ------------------------------------------------------------------

    -- Skal bekræftede exploits (LEVEL >= BanConfidenceLevel) føre til permanent ban?
    -- Hvis false, bliver overtrædelser stadig opdaget, blokeret (plate revertes) og
    -- logget — spilleren bliver bare ikke banned automatisk.
    BanEnabled = true,

    -- Skal bans overhovedet skrives til/læses fra databasen (masitz_anticheat_bans)?
    -- Skal reelt altid være true - findes som config for gennemsigtighed/debugging,
    -- ligesom CheckOwnership. Hvis false: BanPlayer() bliver aldrig kaldt, og
    -- ban-tjekket ved playerConnecting springes helt over.
    SaveBans = true,

    -- Hvilket detection-level der som minimum kræves for automatisk permanent ban.
    -- Se server.lua "DETECTION LEVELS" for hvad hvert niveau betyder.
    -- Standard = 4 (kun stærk/bekræftet evidens banner automatisk).
    BanConfidenceLevel = 4,

    -- Hvis en spiller gentagne gange trigger'er LAVERE-niveau mistænkelig aktivitet
    -- (som ikke i sig selv er nok til ban) inden for et tidsvindue, kan systemet
    -- eskalere til ban alligevel. Dette forhindrer at en cheater "farmer" lige under
    -- ban-tærsklen. Sat konservativt for at undgå false positives.
    EscalateRepeatOffences = true,
    RepeatOffenceThreshold = 3,        -- antal suspicious events før eskalering
    RepeatOffenceWindowMs = 5 * 60 * 1000, -- inden for 5 minutter

    -- Skal spilleren droppes fra serveren når de bliver banned (ud over DB-banned)?
    KickOnBan = true,

    -- ------------------------------------------------------------------
    -- DISCORD LOGGING
    -- ------------------------------------------------------------------

    DiscordLogging = true,

    -- Fallback webhook, bruges hvis en specifik webhook nedenfor er tom.
    Webhook = "",

    -- Valgfrie separate webhooks pr. kategori (lad stå tomme for at bruge Webhook ovenfor).
    WebhookLegit = "",       -- 🟢 legitime nummerpladeændringer
    WebhookSuspicious = "",  -- 🟡 suspicious activity
    WebhookViolation = "",   -- 🔴 confirmed anti-cheat violations
    WebhookBan = "",         -- 🚨 bans

    DiscordUsername = "Masitz-Anticheat",
    DiscordAvatar = "",

    -- ------------------------------------------------------------------
    -- LEGITIM NUMMERPLADEÆNDRING / ITEM
    -- ------------------------------------------------------------------

    -- Itemet spilleren skal besidde for at få lov til at ændre en nummerplade.
    PlateItem = "vehicle_plate",

    -- Skal vehicle_plate item-besiddelse kontrolleres server-side (via ox_inventory)?
    CheckItem = true,

    -- Skal AuthorizePlateChange selv fjerne itemet fra spillerens inventory,
    -- som en del af den atomiske autorisation? (Anbefalet: true — så er det
    -- garanteret at itemet reelt bliver brugt, uanset hvad det kaldende
    -- nummerplade-script selv gør/glemmer.)
    ConsumeItemOnAuthorize = true,

    -- ------------------------------------------------------------------
    -- OWNERSHIP / DUPLICATE
    -- ------------------------------------------------------------------

    -- Skal ejerskab af køretøjet (owned_vehicles.owner) verificeres server-side?
    -- Bør ALTID være true. Findes kun som config for gennemsigtighed/debugging.
    CheckOwnership = true,

    -- Skal der tjekkes for at den nye nummerplade allerede findes i owned_vehicles?
    CheckDuplicatePlates = true,

    -- ------------------------------------------------------------------
    -- PLATE VALIDERING / NORMALISERING
    -- ------------------------------------------------------------------

    MinPlateLength = 2,
    MaxPlateLength = 8, -- matcher GTA/FiveM's praktiske plate-længde (owned_vehicles.plate er VARCHAR(12))

    -- Kun store bogstaver, tal og mellemrum er tilladt i en plate efter normalisering.
    -- (Normalisering: trim, upper-case, kollaps multiple mellemrum til ét.)
    PlateCharsetPattern = "^[A-Z0-9 ]+$",

    -- ------------------------------------------------------------------
    -- VEHICLE TRACKING / DETECTION PERFORMANCE
    -- ------------------------------------------------------------------

    -- Hvor ofte (ms) den lette periodiske sikkerhedsscanning kører over
    -- KUN de køretøjer systemet allerede tracker (ikke alle entities på kortet).
    -- Event-drevne tjek (spiller sætter sig ind i et køretøj, entity oprettes)
    -- sker øjeblikkeligt uanset dette interval — sweepet er blot et safety-net.
    SweepIntervalMs = 45000,

    -- Hvor længe (ms) der ventes efter et køretøj spawnes, før systemet læser
    -- dets plate og binder det til en owned_vehicles-record. Giver garage-scriptet
    -- tid til at sætte pladen efter spawn, så vi ikke fejlagtigt tracker en
    -- midlertidig/tom plate som "baseline".
    SpawnBindDelayMs = 2500,

    -- Rate-limit (ms) for det (ikke-trusted) client-side hint-event, der beder
    -- serveren om at tjekke et køretøj med det samme i stedet for at vente på
    -- næste sweep. Forhindrer event-spam. Hintet ændrer ALDRIG noget i sig selv —
    -- det udløser blot en server-autoritativ re-verificering.
    ClientHintRateLimitMs = 3000,

    -- Et køretøj, der IKKE findes i owned_vehicles (fx en tilfældig spawned/stjålet
    -- bil), bliver kun overvåget mens en spiller reelt sidder i den (og et kort
    -- stykke tid efter). Dette lukker Attack 2 (skifte en stjålet bils plade til en
    -- andens registrerede plade) uden at systemet behøver tracke hver eneste
    -- ambient/NPC-bil på hele kortet permanent.
    EnableUnregisteredVehicleWatch = true,
    UnregisteredWatchWindowSec = 300, -- hvor længe et uregistreret køretøj forbliver overvåget uden en driver

    -- ------------------------------------------------------------------
    -- ADMIN / STAFF
    -- ------------------------------------------------------------------

    -- ESX-grupper der må bruge /anticheat_status kommandoen (server-side check).
    -- Tom liste = ingen (kommandoen findes stadig, men afvises for alle).
    AdminGroups = { "admin", "superadmin" },

    -- ------------------------------------------------------------------
    -- FRAMEWORK / INTEGRATION
    -- ------------------------------------------------------------------

    -- Navnet på ESX-resourcen, bruges til at hente det delte ESX-object.
    ESXResourceName = "es_extended",
}
