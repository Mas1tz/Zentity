-- ============================================================
--  Masitz-garage | config.lua
--  ESX Legacy · ox_lib · oxmysql · ox_fuel · Lua 5.4
--  Rework af MM-garage (kc_garage) — se README.md for ændringslog.
-- ============================================================

Config = {}

-- ─── DEBUG ───────────────────────────────────────────────────
Config.Debug = false   -- true = print verbose server/client logs

-- ─── FRAMEWORK ───────────────────────────────────────────────
-- Kun ESX Legacy understøttes i dette rework
Config.Framework = 'esx'

-- ─── FUEL ────────────────────────────────────────────────────
Config.FuelSystem     = 'ox_fuel'   -- 'ox_fuel' | 'LegacyFuel' | 'cdn-fuel' | nil
Config.DefaultFuel    = 100.0
Config.SaveFuel       = true

-- ─── VEHICLE HEALTH ──────────────────────────────────────────
Config.SaveEngineHealth = true
Config.SaveBodyHealth   = true
Config.DefaultEngine    = 1000.0
Config.DefaultBody      = 1000.0

-- ─── SPAWN ───────────────────────────────────────────────────
Config.SpawnClearRadius  = 4.0    -- Radius (m) der tjekkes for blokerende køretøjer
Config.SpawnWaitTimeout  = 8000   -- ms maks at vente på entity creation
Config.SpawnNetTimeout   = 5000   -- ms maks at vente på network ownership

-- ─── ZONES ───────────────────────────────────────────────────
Config.AccessDistance = 2.5       -- Aktivér adgangszone
Config.StoreDistance  = 4.5       -- Aktivér parkérzone
Config.DrawDistance   = 22.0      -- Marker renderdistance

-- ─── PROGRESS BARS ───────────────────────────────────────────
Config.StoreDuration  = 3000      -- ms parkering tager
Config.SpawnDuration  = 0         -- 0 = ingen bar ved spawn

-- ─── IMPOUND ─────────────────────────────────────────────────
Config.ImpoundEnabled    = true
Config.ImpoundBaseFee    = 2500   -- Grundgebyr for at hente bil ud
Config.ImpoundPerHour    = 150    -- Ekstra kr. pr påbegyndt time
Config.ImpoundMaxFee     = 25000  -- Maks gebyr

-- ─── KEY SYSTEM ──────────────────────────────────────────────
-- Eksternt key-script (MM-vehiclekeys) — UÆNDRET, blot fortsat
-- brugt. Export-navnene (Masitz_giveKey / Masitz_removeKey) er
-- MM-vehiclekeys' EGNE eksisterende export-navne og må ikke ændres.
Config.KeySystem         = true
Config.KeyExport         = 'MM-vehiclekeys'   -- Resource-navn

-- ─── NAVNGIVNING (§5) ────────────────────────────────────────
Config.VehicleName = {
    maxLength = 32,   -- maks. antal tegn i et brugerdefineret bilnavn
    -- Tilladte tegn: bogstaver (inkl. æøå), tal, mellemrum og let
    -- tegnsætning. Alt andet fjernes server-side før gemning.
    allowedPattern = '[^%a%d æøåÆØÅ%-%.,\'!]',
}

-- ─── SALG (§7-§11) ───────────────────────────────────────────
Config.Sale = {
    minPrice     = 1,           -- kr. — 0/negative priser er ikke tilladt
    maxPrice     = 500000000,   -- kr. — sanity-cap mod fejltastning/exploit
    timeoutSec   = 60,          -- hvor længe et tilbud står åbent hos køberen
    sweepInterval = 15000,      -- ms — hvor tit udløbne handler ryddes op
}

-- ─── GARAGE-FLYTNING / TRANSPORT (§14-§16) ───────────────────
-- Serveren beregner ALTID selv den endelige pris — dette er kun
-- den konfigurerbare formel. price = minPrice + (afstand i km) * pricePerKm,
-- derefter clampet til [minPrice, maxPrice].
Config.GarageTransfer = {
    enabled    = true,
    minPrice   = 50000,
    maxPrice   = 150000,
    pricePerKm = 11000,
    -- Hvilken kontotype transport-/flytteprisen trækkes fra.
    -- 'bank' | 'money'
    paymentAccount = 'bank',
}

-- ─── DISCORD LOGGING (§12) ────────────────────────────────────
-- Webhook-URLs ligger KUN her (server-side config) — aldrig i
-- client-kode. Sæt enabled = false for helt at slå logging fra.
Config.Logging = {
    enabled = false,

    webhooks = {
        sales     = '',   -- bilsalg (spiller-til-spiller)
        keys      = '',   -- nøgler givet
        plates    = '',   -- nummerpladeændringer (API/eksport-drevet)
        garage    = '',   -- hentet/parkeret/flyttet mellem garager
        purchases = '',   -- bilkøb (fra en bilforhandler-resource via export)
        impound   = '',   -- impound + release
    },

    username = 'Masitz-garage',
}

-- ─── MARKERS ─────────────────────────────────────────────────
Config.AccessMarker = {
    type   = 2,
    size   = vec3(0.6, 0.6, 0.6),
    height = 0.2,
    r=0, g=132, b=255, a=200,
    text   = '[E] Garage'
}
Config.StoreMarker = {
    type   = 27,
    size   = vec3(5.0, 5.0, 1.5),
    height = -0.9,
    r=0, g=200, b=100, a=140,
    text   = '[E] Parkér køretøj'
}
Config.BoatAccessMarker = {
    type   = 2,
    size   = vec3(0.6, 0.6, 0.6),
    height = 0.2,
    r=0, g=180, b=255, a=200,
    text   = '[E] Marina'
}
Config.BoatStoreMarker = {
    type   = 27,
    size   = vec3(5.0, 5.0, 1.5),
    height = -0.9,
    r=0, g=140, b=255, a=140,
    text   = '[E] Fortøj båd'
}
Config.ImpoundMarker = {
    type   = 2,
    size   = vec3(0.6, 0.6, 0.6),
    height = 0.1,
    r=255, g=59, b=92, a=255,
    text   = '[E] Impound'
}

-- ─── BLIPS ───────────────────────────────────────────────────
Config.GarageBlip = {
    car   = { sprite=357, scale=0.8, colour=18, label='Garage' },
    plane = { sprite=569, scale=0.8, colour=18, label='Hangar' },
    boat  = { sprite=473, scale=0.8, colour=18, label='Bådeplads' },
}

-- ─── IMPOUND BLIP ───────────────────────────────────────────────
Config.ImpoundBlip = { sprite=317, scale=0.8, colour=6, label='Impound' }

-- ─── BOAT BLIP ───────────────────────────────────────────────
Config.BoatBlip = { sprite=410, scale=0.8, colour=3, label='Marina' }

-- ─── GARAGER ─────────────────────────────────────────────────
-- access : vec3 — "Åbn garage"-zone
-- store  : vec3 — "Parkér"-zone
-- spawn  : vec4 — Spawn-koordinater (x,y,z,heading)
-- type   : 'car' | 'plane' | 'boat'
-- blip   : bool
-- label  : Vises i UI

Config.Garages = {

    ['midtby'] = {
        access = vec3(213.73,   -809.17,   31.01),
        store  = vec3(223.23,   -762.35,   30.82),
        spawn  = vec4(230.75,   -795.95,   30.58, 0.0),
        type   = 'car', blip = true,
        label  = 'Midtby Garage'
    },
    ['stranden'] = {
        access = vec3(-1184.33, -1509.55,  4.65),
        store  = vec3(-1198.41, -1483.03,  4.38),
        spawn  = vec4(-1183.57, -1490.05,  4.38, 0.0),
        type   = 'car', blip = true,
        label  = 'Strand Garage'
    },
    ['shambles'] = {
        access = vec3(996.92,   -2360.12,  30.51),
        store  = vec3(1015.70,  -2331.05,  30.51),
        spawn  = vec4(1013.73,  -2364.30,  30.51, 0.0),
        type   = 'car', blip = true,
        label  = 'Shambles Garage'
    },
    ['eclipse'] = {
        access = vec3(-570.73,   310.94,   84.50),
        store  = vec3(-567.14,   329.43,   84.45),
        spawn  = vec4(-607.39,   337.19,   85.12, 0.0),
        type   = 'car', blip = true,
        label  = 'Eclipse Garage'
    },
    ['great_ocean'] = {
        access = vec3(-200.18,  6234.50,   31.50),
        store  = vec3(-200.58,  6214.32,   31.49),
        spawn  = vec4(-193.04,  6225.61,   31.49, 0.0),
        type   = 'car', blip = true,
        label  = 'Great Ocean Garage'
    },
    ['panorama_drive'] = {
        access = vec3(1649.30,  3567.13,   35.39),
        store  = vec3(1634.60,  3565.22,   35.27),
        spawn  = vec4(1608.83,  3602.72,   35.15, 0.0),
        type   = 'car', blip = true,
        label  = 'Panorama Drive'
    },
    ['new_empire'] = {
        access = vec3(-942.24,  -2956.12,  13.95),
        store  = vec3(-974.92,  -2997.53,  13.95),
        spawn  = vec4(-974.80,  -3298.94,  14.05, 0.0),
        type   = 'plane', blip = true,
        label  = 'New Empire Hangar'
    },
    ['mirror_park'] = {
        access = vec3(1146.58, -464.30, 66.67),
        store  = vec3(1153.29, -473.52, 66.55),
        spawn  = vec4(1153.29, -473.52, 66.55, 0.0),
        type   = 'car', blip = true,
        label  = 'Mirror Park Garage'
    },
    ['casaino'] = {
        access = vec3(886.89, 0.15, 78.76),
        store  = vec3(883.62, -4.78, 78.76),
        spawn  = vec4(875.03, -16.02, 78.76, 0.0),
        type   = 'car', blip = true,
        label  = 'Casino Garage'
    },
    ['weazel_news'] = {
        access = vec3(-591.54, -890.00, 25.94),
        store  = vec3(-601.62, -889.26, 25.24),
        spawn  = vec4(-601.62, -889.26, 25.24, 0.0),
        type   = 'car', blip = true,
        label  = 'Weazel Garage'
    },
    ['san_andreas'] = {
        access = vec3(-1159.00, -740.07, 19.89),
        store  = vec3(-1171.52, -743.97, 19.67),
        spawn  = vec4(-1166.63, -747.73, 19.36, 0.0),
        type   = 'car', blip = true,
        label  = 'San Andreas Avenue Garage'
    },
    ['vinewood'] = {
        access = vec3(596.72, 91.59, 93.13),
        store  = vec3(602.33, 108.82, 92.91),
        spawn  = vec4(610.08, 94.73, 92.52, 0.0),
        type   = 'car', blip = true,
        label  = 'Vinewood Boulevard Garage'
    },
    ['Occupation'] = {
        access = vec3(275.61, -344.91, 45.17),
        store  = vec3(275.10, -328.75, 44.92),
        spawn  = vec4(289.32, -340.82, 44.92, 0.0),
        type   = 'car', blip = true,
        label  = 'Occupation Avenue Garage'
    },

    -- ── NYE GARAGER (§17) — alle spillere har adgang ──────────
    ['downtown'] = {
        access = vec3(56.28,   -876.45, 30.66),
        store  = vec3(41.22,   -885.41, 30.24),
        spawn  = vec4(58.01,   -860.72, 30.65, 0.0),
        type   = 'car', blip = true,
        label  = 'Downtown Garage'
    },
    ['route68_motel'] = {
        access = vec3(1142.31, 2665.43, 38.16),
        store  = vec3(1127.45, 2668.63, 38.04),
        spawn  = vec4(1137.86, 2663.77, 38.00, 0.0),
        type   = 'car', blip = true,
        label  = 'Route 68 Motel Garage'
    },
    ['faengslet'] = {
        access = vec3(1852.83, 2581.47, 45.67),
        store  = vec3(1861.28, 2574.96, 45.67),
        spawn  = vec4(1872.60, 2584.70, 45.67, 0.0),
        type   = 'car', blip = true,
        label  = 'Fængsels Garage'
    },
    ['bilforhandler'] = {
        access = vec3(-8.82,   -1090.99, 26.67),
        store  = vec3(-12.90,  -1100.11, 26.67),
        spawn  = vec4(-11.98,  -1083.88, 26.67, 0.0),
        type   = 'car', blip = true,
        label  = 'Bilforhandler Garage'
    },
}

-- ─── IMPOUNDS ────────────────────────────────────────────────
Config.Impounds = {

    ['innocence'] = {
        access = vec3(409.28,   -1623.05, 29.29),
        spawn  = vec4(407.17,   -1645.23, 29.29, 0.0),
        type   = 'car', blip = true,
        label  = 'Innocence Impound'
    },
    ['vespucci'] = {
        access = vec3(-1057.94, -840.68, 5.04),
        spawn  = vec4(-1052.33, -856.46, 4.87, 0.0),
        type   = 'car', blip = true,
        label  = 'Vespucci Impound'
    },
    ['paleto'] = {
        access = vec3(-456.84,  6017.93, 31.49),
        spawn  = vec4(-467.41,  6015.98, 31.34, 0.0),
        type   = 'car', blip = true,
        label  = 'Paleto Impound'
    },
    ['zancudo'] = {
        access = vec3(1852.51,  3706.90, 33.25),
        spawn  = vec4(1864.84,  3700.91, 33.54, 0.0),
        type   = 'car', blip = true,
        label  = 'Fort Zancudo Impound'
    },
    ['pista_1'] = {
        access = vec3(-1229.44, -3377.81, 13.95),
        spawn  = vec4(-1270.81, -3376.13, 13.94, 0.0),
        type   = 'plane', blip = true,
        label  = 'Airstrip Impound'
    },
    ['adam_apple_blvd'] = {
        access = vec3(-191.98, -1162.27, 23.67),
        spawn = vec4(-147.44, -1168.81, 23.77, 0.0),
        type = 'car', blip = true,
        label = 'Adam\'s Apple Boulevard'
    }
}

-- ─── BOAT GARAGES ────────────────────────────────────────────────
Config.Boat = {

    ['shank_st'] = {
        access = vec3(-772.4, -1430.9, 0.5),
        store  = vec3(-798.4, -1456.0, 0.0),
        spawn  = vec4(-785.39, -1426.3, 0.0, 146.0),
        type   = 'boat',
        blip   = true,
        label  = 'Shank St Marina'
    },

    ['catfish_view'] = {
        access = vec3(3864.9, 4463.9, 1.6),
        store  = vec3(3857.0, 4446.9, 0.0),
        spawn  = vec4(3854.4, 4477.2, 0.0, 273.0),
        type   = 'boat',
        blip   = true,
        label  = 'Catfish View Marina'
    },

    ['great_ocean'] = {
        access = vec3(-1614.0, 5260.1, 2.8),
        store  = vec3(-1600.3, 5261.9, 0.0),
        spawn  = vec4(-1622.5, 5247.1, 0.0, 21.0),
        type   = 'boat',
        blip   = true,
        label  = 'Great Ocean Marina'
    },

    ['north_calafia'] = {
        access = vec3(712.6, 4093.3, 33.7),
        store  = vec3(705.1, 4110.1, 30.2),
        spawn  = vec4(712.8, 4080.2, 29.3, 181.0),
        type   = 'boat',
        blip   = true,
        label  = 'North Calafia Dock'
    },

    ['elysian_fields'] = {
        access = vec3(23.8, -2806.8, 4.8),
        store  = vec3(-1.0, -2799.2, 0.5),
        spawn  = vec4(23.3, -2828.6, 0.8, 181.0),
        type   = 'boat',
        blip   = true,
        label  = 'Elysian Fields Marina'
    },

    ['barbareno_rd'] = {
        access = vec3(-3427.3, 956.9, 7.3),
        store  = vec3(-3436.5, 946.6, 0.3),
        spawn  = vec4(-3448.9, 953.8, 0.0, 75.0),
        type   = 'boat',
        blip   = true,
        label  = 'Barbareno Marina'
    }
}
