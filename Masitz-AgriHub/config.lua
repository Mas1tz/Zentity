-- ============================================================
--  Masitz-AgriHub | config.lua
--  ESX Legacy · ox_lib · ox_target · ox_inventory · oxmysql
--  ALT der er relevant for drift styres herfra.
-- ============================================================

Config = Config or {}
Config.Agri = Config.Agri or {}

-- ─── DEBUG ───────────────────────────────────────────────────
Config.Agri.Debug = false

-- ─── VINTER ──────────────────────────────────────────────────
-- Styrer UDELUKKENDE om tractor3 kan lejes (se Config.Agri.Rentals).
Config.Agri.IsWinter = false

-- ─── ADMIN ───────────────────────────────────────────────────
-- SUPER_ADMIN afgøres KUN server-side (server/access.lua) ud fra denne
-- Discord ID sammenlignet mod GetPlayerIdentifiers(src). Bruges ALDRIG
-- client-side og sendes ALDRIG til NUI'en.
Config.Agri.Admin = {
    discordId = '1529563765870301217',
}

-- ─── AGRIHUB COMPUTER ────────────────────────────────────────
Config.Agri.Computer = {
    coords   = vec3(911.38, -1513.43, 32.14),
    distance = 1.5,
    label    = 'Åbn AgriHub',
    icon     = 'fa-solid fa-desktop',
}

-- ============================================================
--  ITEMS — DU udfylder selv item-navnene (ox_inventory items).
--  Alle item-tjek sker server-side ud fra disse nøgler.
-- ============================================================
Config.Agri.Items = {
    fertilizer     = 'fertilizer',      -- kunstgødning
    pesticide      = 'pesticide',       -- sprøjtemiddel
    diesel         = 'diesel_canister', -- diesel (kun reference — selve dieseltransporten kører via tanker/tanker2)
    seeds          = 'seeds',
    animal_feed    = 'animal_feed',
    equipment_bale = 'bale_equipment',
    equipment_grain= 'grain_equipment',
    equipment_rake = 'rake_equipment',
}

-- ============================================================
--  SHOP — varer der kan købes på AgriHub-computeren.
--  Pris beregnes ALTID server-side ud fra denne tabel — clienten
--  kan aldrig sende sin egen pris.
-- ============================================================
Config.Agri.Shop = {
    {
        id       = 'fertilizer',
        label    = 'Kunstgødning',
        item     = 'fertilizer',
        price    = 5000,   -- pr. stk
        maxCart  = 50,
        category = 'fertilizer',
        icon     = 'fa-solid fa-wheat-awn',
    },
    {
        id       = 'pesticide',
        label    = 'Sprøjtekemikalier',
        item     = 'pesticide',
        price    = 6500,
        maxCart  = 50,
        category = 'chemicals',
        icon     = 'fa-solid fa-flask',
    },
    {
        id       = 'seeds',
        label    = 'Såsæd',
        item     = 'seeds',
        price    = 2500,
        maxCart  = 100,
        category = 'general',
        icon     = 'fa-solid fa-seedling',
    },
    {
        id       = 'animal_feed',
        label    = 'Dyrefoder',
        item     = 'animal_feed',
        price    = 1800,
        maxCart  = 100,
        category = 'general',
        icon     = 'fa-solid fa-wheat-awn-circle-exclamation',
    },
}

-- ============================================================
--  LEVERINGSKØRETØJER (§17) — kunstgødning/sprøjtemidler/generel fragt
-- ============================================================
Config.Agri.DeliveryVehicles = {
    'pounder2', 'mule3', 'mule4', 'mule5', 'nspeedo', 'youga2', 'rumpo2',
    'speedo4', 'pony', 'gburrito2', 'burrito', 'burrito2', 'burrito3',
    'burrito4', 'boxville', 'boxville3', 'slamvan2',
}

-- Burrito må kun bruges med bestemte liveries — ALLE undtagen nummer 1.
-- GTA/FiveM liveries er 0-indekserede (SET_VEHICLE_LIVERY(veh, index)),
-- så "nummer 1" i almindelig tale = index 0. Listen herunder er derfor
-- index 1 og opefter (dvs. 0 er ekskluderet). Juster efter hvor mange
-- liveries burrito faktisk har på jeres server (verificér in-game).
Config.Agri.VehicleLiveries = {
    burrito = { 1, 2, 3, 4, 5, 6, 7, 8, 9 },
}

-- ============================================================
--  LANDMÆND — hver landmand er individuelt konfigurerbar.
-- ============================================================
Config.Agri.Farmers = {
    {
        id        = 'hansen',
        name      = 'Landmand Hansen',
        pedModel  = `a_m_m_farmer_01`,
        coords    = vec3(2427.9, 4964.3, 46.4),
        heading   = 130.0,
        buys      = { 'fertilizer' },          -- køber meget kunstgødning
        sells     = {},
        tasks     = { 'diesel', 'fertilizer_delivery' },
        machines  = { 'tractor', 'bulldozer' },
        animalTypes = {},
        target    = { distance = 2.5, icon = 'fa-solid fa-user' },
    },
    {
        id        = 'jensen',
        name      = 'Landmand Jensen',
        pedModel  = `a_m_m_farmer_01`,
        coords    = vec3(-273.9, 6636.9, 7.5),
        heading   = 45.0,
        buys      = { 'pesticide' },           -- køber sprøjtemidler, bestiller maskiner
        sells     = {},
        tasks     = { 'pesticide_delivery', 'machinery_npc', 'equipment_delivery' },
        machines  = { 'cutter', 'mixer2', 'tractor2' },
        animalTypes = {},
        target    = { distance = 2.5, icon = 'fa-solid fa-user' },
    },
    {
        id        = 'andersen',
        name      = 'Landmand Andersen',
        pedModel  = `a_f_m_farmgirl_01`,
        coords    = vec3(1697.6, 4924.7, 42.0),
        heading   = 200.0,
        buys      = { 'animal_feed' },
        sells     = { 'cattle' },              -- sender dyr
        tasks     = { 'animal_transport' },
        machines  = { 'towtruck' },
        animalTypes = { 'cattle', 'sheep', 'goat' },
        target    = { distance = 2.5, icon = 'fa-solid fa-user' },
    },
    {
        id        = 'moeller',
        name      = 'Landmand Møller',
        pedModel  = `a_m_m_farmer_01`,
        coords    = vec3(-97.4, 2854.9, 58.2),
        heading   = 300.0,
        buys      = { 'seeds', 'fertilizer' },
        sells     = { 'pigs', 'chicken' },
        tasks     = { 'diesel', 'animal_transport', 'machinery_npc' },
        machines  = { 'dump', 'tiptruck', 'forklift' },
        animalTypes = { 'pig', 'chicken', 'duck', 'goose' },
        target    = { distance = 2.5, icon = 'fa-solid fa-user' },
    },
}

-- Slagteri/auktion — faste destinationer for dyretransport (§43)
Config.Agri.AnimalDestinations = {
    { id = 'slaughterhouse', label = 'Slagteriet', coords = vec3(2036.9, 3131.8, 45.2) },
    { id = 'auction',        label = 'Dyreauktionen', coords = vec3(1682.9, 4832.9, 42.0) },
}

-- ============================================================
--  DIESEL-FRAGT (§20-§24)
-- ============================================================
Config.Agri.Diesel = {
    trucks         = { 'hauler', 'packer', 'phantom' },
    autoAssign     = false,   -- true = server vælger automatisk, false = spiller vælger selv
    trailerModels  = { 'tanker', 'tanker2' },
    spawnCoords    = vec4(905.1, -1521.6, 31.9, 250.0),
    returnZone     = { coords = vec3(905.1, -1521.6, 31.9), distance = 4.0 },
    route          = { minStops = 1, maxStops = 4 },
    rewardPerStop  = 40000,
    baseReward     = 30000,
    unloadDuration = 8000, -- ms, progress bar
}

-- ============================================================
--  REDSKABS-OPGAVER (§39-§40)
-- ============================================================
Config.Agri.Equipment = {
    towVehicle    = 'tractor2',
    trailers      = { 'baletrailer', 'graintrailer', 'raketrailer' },
    spawnCoords   = vec4(905.1, -1521.6, 31.9, 250.0),
    reward        = { min = 60000, max = 110000 },
}

-- ============================================================
--  DYRETRANSPORT (§41-§43)
-- ============================================================
Config.Agri.Animals = {
    vehicle = 'benson2',
    spawnCoords = vec4(905.1, -1521.6, 31.9, 250.0),
    types = {
        { id = 'cattle',  label = 'Kvæg' },
        { id = 'pig',     label = 'Svin' },
        { id = 'sheep',   label = 'Får' },
        { id = 'goat',    label = 'Geder' },
        { id = 'horse',   label = 'Heste' },
        { id = 'chicken', label = 'Høns' },
        { id = 'duck',    label = 'Ænder' },
        { id = 'goose',   label = 'Gæs' },
        { id = 'bees',    label = 'Honningbier' },
    },
    reward = { min = 70000, max = 180000 },
}

-- ============================================================
--  MASKINUDLEJNING — priser (§25, §30)
--  tractor3 er vinter-special (styret af Config.Agri.IsWinter).
-- ============================================================
Config.Agri.Rentals = {
    bulldozer  = { label = 'Bulldozer',           deposit = 250000, rent = 100000, winterOnly = false },
    cutter     = { label = 'Cutter',              deposit = 180000, rent = 80000,  winterOnly = false },
    dump       = { label = 'Dumper',              deposit = 220000, rent = 90000,  winterOnly = false },
    mixer2     = { label = 'Cementblander',       deposit = 200000, rent = 85000,  winterOnly = false },
    tiptruck   = { label = 'Tipvogn',             deposit = 190000, rent = 75000,  winterOnly = false },
    tiptruck2  = { label = 'Tipvogn (stor)',      deposit = 230000, rent = 95000,  winterOnly = false },
    forklift   = { label = 'Gaffeltruck',         deposit = 90000,  rent = 40000,  winterOnly = false },
    towtruck2  = { label = 'Kranvogn',            deposit = 260000, rent = 110000, winterOnly = false },
    towtruck   = { label = 'Bugseringsvogn',      deposit = 150000, rent = 65000,  winterOnly = false },
    mower      = { label = 'Plæneklipper',        deposit = 60000,  rent = 25000,  winterOnly = false },
    scrap      = { label = 'Skrothåndterer',      deposit = 210000, rent = 88000,  winterOnly = false },
    tractor    = { label = 'Traktor',             deposit = 50000,  rent = 25000,  winterOnly = false },
    tractor2   = { label = 'Traktor (arbejde)',   deposit = 70000,  rent = 32000,  winterOnly = false },
    tractor3   = { label = 'Traktor (vinter)',    deposit = 500000, rent = 220000, winterOnly = true  },
}

Config.Agri.RentalSpawnCoords = vec4(905.1, -1521.6, 31.9, 250.0)
Config.Agri.RentalReturnZone  = { coords = vec3(905.1, -1521.6, 31.9), distance = 4.0 }

-- Lejeperiode-grænser (bruges når kontrakter oprettes/forlænges)
Config.Agri.ContractRules = {
    minDurationHours   = 6,
    maxDurationHours   = 24 * 14,     -- 14 dage
    defaultDurationHours = 24 * 3,    -- 3 dage, hvis udlejer ikke vælger andet
    approvalTimeoutSec = 300,         -- lejer har 5 minutter til at godkende
}

-- ============================================================
--  GENERISK TASK-ENGINE — én motor, flere typer.
--  Alle typer deler samme livscyklus (server/tasks.lua):
--  available -> active -> completed/expired/cancelled.
-- ============================================================
Config.Agri.TaskTypes = {
    diesel = {
        label        = 'Diessellevering',
        icon         = '🚛',
        expirySec    = 1800,
        vehicleGroup = 'diesel',
    },
    fertilizer_delivery = {
        label        = 'Gødningslevering',
        icon         = '🌾',
        expirySec    = 1800,
        vehicleGroup = 'delivery',
        item         = 'fertilizer',
        rewardPerUnit = 4000,
        minUnits = 10, maxUnits = 30,
    },
    pesticide_delivery = {
        label        = 'Kemikalielevering',
        icon         = '🧪',
        expirySec    = 1800,
        vehicleGroup = 'delivery',
        item         = 'pesticide',
        rewardPerUnit = 4500,
        minUnits = 10, maxUnits = 30,
    },
    equipment_delivery = {
        label        = 'Redskabslevering',
        icon         = '🔧',
        expirySec    = 1800,
        vehicleGroup = 'equipment',
    },
    animal_transport = {
        label        = 'Dyretransport',
        icon         = '🐄',
        expirySec    = 1800,
        vehicleGroup = 'animals',
    },
    machinery_npc = {
        label        = 'Maskinlevering',
        icon         = '🚜',
        expirySec    = 1800,
        vehicleGroup = 'rental',
    },
}

-- Hvor mange ledige opgaver af hver type der maksimalt findes samtidig,
-- og hvor tit puljen genopfyldes (kun brugt til at AFGØRE om der skal
-- genereres en ny opgave NÅR spilleren åbner NUI'en/opgave-listen —
-- ikke en baggrunds-loop).
Config.Agri.TaskPool = {
    maxPerType         = 3,
    generateOnNuiOpen  = true,
}

-- ============================================================
--  PLATES
-- ============================================================
Config.Agri.Plates = {
    rentalPrefix = 'RENTAL',   -- RENTAL01 .. RENTAL99
    jobPrefix    = 'AGRI',     -- AGRI001 .. AGRI999
    maxLength    = 8,
}

-- ============================================================
--  MM-vehiclekeys integration
-- ============================================================
Config.Agri.Keys = {
    enabled  = true,
    resource = 'MM-vehiclekeys',
    giveExport   = 'Masitz_giveKey',
    removeExport = 'Masitz_removeKey',
}

-- ============================================================
--  LOGGING — Discord webhooks. KUN server-side, ALDRIG i client/NUI.
-- ============================================================
Config.Agri.Logging = {
    enabled = false,
    username = 'AgriHub',

    webhooks = {
        access     = '',
        login      = '',
        purchases  = '',
        deliveries = '',
        rentals    = '',
        contracts  = '',
        diesel     = '',
        animals    = '',
        machinery  = '',
        payments   = '',
        errors     = '',
        security   = '',
    },
}

-- ============================================================
--  PERFORMANCE
-- ============================================================
Config.Agri.Performance = {
    -- Meget sjælden, billig sweep for: udløbne kontrakter (lazy expiry
    -- dækker det meste, dette er et sikkerhedsnet), orphaned spawnede
    -- køretøjer (spiller disconnectede midt i en opgave/udlejning).
    -- Se README "Performance" for hvorfor dette IKKE kan være 0 uden
    -- at miste funktionalitet.
    cleanupIntervalMs = 600000, -- 10 minutter
}
