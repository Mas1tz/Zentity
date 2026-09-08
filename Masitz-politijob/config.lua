-- ============================================================
-- MM-PolitiJob v3.0 – config.lua
-- Alt config-drevet. Ingen hardcoded værdier i scripts.
-- ============================================================

Config = {}

-- ── FRAMEWORK ────────────────────────────────────────────────
-- "auto" | "esx" | "qb"
Config.Framework = "auto"

-- ── POLITI JOB NAVNE ─────────────────────────────────────────
Config.PoliceJobs = { 'police', 'sheriff' }

-- ── HANDCUFF ─────────────────────────────────────────────────
Config.HandcuffProp       = 'p_high_tier_handcuff_s'
Config.HandcuffMaxDistance = 3.0   -- Meter – maks afstand til at håndjerne

-- ── GSR ──────────────────────────────────────────────────────
Config.GSRTimeout = 300000         -- ms – 5 min

-- ── PANIC ────────────────────────────────────────────────────
Config.PanicKey      = 'Y'         -- Tast
Config.PanicCooldown = 30000       -- ms – 30 sek cooldown
Config.PanicBlipTime = 30000       -- ms – blip fjernes efter 30 sek
Config.PanicSound    = 'Beep_Red'  -- FrontendSounds sound-navn
Config.PanicMeRadius = 20.0        -- Meter – hvem kan se /me-beskeden

-- ── DUTY ─────────────────────────────────────────────────────
Config.DutyMinGrade  = 0           -- Mindste grade der kræves for duty

-- ── INTERAKTION – MAX AFSTAND ────────────────────────────────
Config.MaxActionDistance = 3.0     -- Meter til GSR, ID, visitering, etc.

-- ── BOSS MENU ────────────────────────────────────────────────
Config.BossMinGrade     = 10
Config.BossTargetCoords = vec3(461.45, -986.07, 30.64)

-- ── DATABASE ─────────────────────────────────────────────────
Config.DB = {
    activityTable = 'police_activity',
}

-- ── DISCORD ──────────────────────────────────────────────────
Config.DiscordWebhook = ''

-- =========================================================
-- 🔹 VÅBENSKAB PEDs
-- =========================================================

Config.Peds = {

    -- =========================================
    -- 🏢 Mission Row Police Department
    -- =========================================
    {
        label   = "MRPD Våbenskab",

        model   = "s_m_y_cop_01",

        coords  = vec3(480.41, -996.74, 30.69),
        heading = 90.0
    },

    -- =========================================
    -- 🌵 Sandy Shores Police Department
    -- =========================================
    {
        label   = "Sandy Våbenskab",

        model   = "s_m_y_cop_01",

        coords  = vec3(1844.52, 3692.08, 34.26),
        heading = 90.0
    },

    -- =========================================
    -- 🌲 Paleto Bay Sheriff Office
    -- =========================================
    {
        label   = "Paleto Våbenskab",

        model   = "s_m_y_cop_01",

        coords  = vec3(-440.04, 5991.97, 31.72),
        heading = 230.0
    }
}

-- ── GARAGE MARKERS ───────────────────────────────────────────
Config.GarageMarker = {
    coords = vec3(459.29, -986.77, 25.70),
    color  = { r = 0, g = 132, b = 255, a = 180 },
    type   = 36,
    size   = vec3(1.5, 1.5, 1.5),
    drawDist   = 20.0,
    interactDist = 2.0,
}

Config.ParkMarker = {
    coords = vec3(458.96, -991.81, 25.70),
    color  = { r = 0, g = 132, b = 255, a = 180 },
    type   = 25,
    size   = vec3(4.0, 4.0, 4.0),
    drawDist   = 20.0,
    interactDist = 2.0,
}

Config.HeliMarker = {
    coords = vec3(461.1, -981.5, 43.6),
    color  = { r = 0, g = 132, b = 255, a = 180 },
    type   = 34,
    size   = vec3(1.2, 1.2, 1.2),
    drawDist   = 20.0,
    interactDist = 2.5,
}

Config.GarageSpawn = { coords = vec3(458.96, -991.81, 25.70), heading = 90.0 }
Config.HeliSpawn   = { coords = vec3(449.5,  -981.2,  43.6),  heading = 90.0 }

-- Maks. antal køretøjer én betjent må have hentet ud samtidig
-- (forhindrer spam-spawn af politikøretøjer).
Config.GarageMaxVehicles = 3

-- ── KØRETØJER ────────────────────────────────────────────────
Config.Vehicles = {
    Marked = {
        { label = "Passat Marked",    model = "passatmarked"  },
        { label = "Mercedes C250",    model = "mercedesc250"  },
        { label = "Explorer Poli",    model = "explorerpoli"  },
    },
    Civil = {
        { label = "Schafter 3 Civil", model = "schafter3civil" },
        { label = "Rebla Civil",      model = "reblacivil"     },
        { label = "V-SSTR Civil",     model = "vsstrcivil"     },
    },
    MC = {
        { label = "BMW MC",           model = "bmwmc"     },
        { label = "Yamaha MC",        model = "yamahamc"  },
    },
    Romeo = {
        { label = "XLSS Civil",       model = "xlsscivil" },
    },
    Heli = {
        { label = "Politi Helikopter", model = "polmav" },
        { label = "Annan Heli",        model = "as350"  },
    },
}

-- ── LOADOUTS ─────────────────────────────────────────────────
Config.LoadoutOrder = {
    "Alm. Beredskab",
    "Romeo",
    "Indsatsleder",
    "Civil",
    "MC",
    "AKS",
    "Politilager"
}

-- ── LOADOUT NUI – WEAPON/ITEM CHIP IKONER ────────────────────
-- Bruges KUN til de små weapon/item-chips på hvert kort. FiveM's
-- NUI (CEF) kan tilgå statiske filer fra ethvert startet resource
-- via "nui://<resource>/<path>", så vi behøver ikke kopiere
-- ox_inventory's billeder ind i dette resource.
-- Skift kun denne hvis din ox_inventory hedder noget andet.
Config.LoadoutImageBasePath = 'nui://ox_inventory/web/images/'

-- Loadout-kortenes HOVEDBILLEDE (den store illustration øverst på
-- kortet) er derimod jeres egne custom billeder, som ligger lokalt
-- i dette resource, fladt i html/image/<fil>.png. Se "image" feltet
-- på hvert loadout nedenfor.

-- =========================================================
-- 🔹 LOADOUTS
-- =========================================================

Config.Loadouts = {

    -- =========================================
    -- 👮 Almindeligt Beredskab
    -- =========================================
    ["Alm. Beredskab"] = {
        icon  = "fa-solid fa-gun",
        image = "almberedskab.png",

        metadata = "Combat Pistol, Gasgranat, Politistav, Lommerlygte, Rustning og Bandager",

        weapons = {
            "WEAPON_COMBATPISTOL",
            "WEAPON_BZGAS",
            "WEAPON_NIGHTSTICK",
            "WEAPON_FLASHLIGHT"
        },

        items = {
            { name = "policearmour",   amount = 3 },
            { name = "bandage",        amount = 5 },
            { name = "medikit",        amount = 2 },
            { name = "politi-ammo9",   amount = 1 },
            { name = "handcuffs",      amount = 1 },
            { name = "politispikes",   amount = 1 },
            { name = "polititaske",    amount = 1 }
        }
    },

    -- =========================================
    -- 🚔 Romeo Enhed
    -- =========================================
    ["Romeo"] = {
        icon  = "fa-solid fa-shield-halved",
        image = "romeo.png",

        metadata = "Carbine Rifle, Lommelygte, Rustning og Førstehjælpskit",

        weapons = {
            "WEAPON_COMBATPISTOL",
            "WEAPON_BZGAS",
            "WEAPON_NIGHTSTICK",
            "WEAPON_FLASHLIGHT",
            "WEAPON_CARBINERIFLE"
        },

        items = {
            { name = "policearmour",   amount = 3 },
            { name = "bandage",        amount = 5 },
            { name = "medikit",        amount = 2 },
            { name = "politi-ammo9",   amount = 1 },
            { name = "politi-ammo3",   amount = 1 },
            { name = "handcuffs",      amount = 1 },
            { name = "politispikes",   amount = 1 },
            { name = "polititaske",    amount = 1 }
        }
    },

    -- =========================================
    -- ⭐ Indsatsleder
    -- =========================================
    ["Indsatsleder"] = {
        icon  = "fa-solid fa-star",
        image = "indsatsleder.png",

        metadata = "SMG, Heavypistol, Rustning",

        weapons = {
            "WEAPON_HEAVYPISTOL",
            "WEAPON_BZGAS",
            "WEAPON_NIGHTSTICK",
            "WEAPON_FLASHLIGHT",
            "WEAPON_SMG"
        },

        items = {
            { name = "policearmour",   amount = 3 },
            { name = "bandage",        amount = 5 },
            { name = "medikit",        amount = 2 },
            { name = "politi-ammo9",   amount = 1 },
            { name = "politi-ammo2",   amount = 1 },
            { name = "handcuffs",      amount = 1 },
            { name = "politispikes",   amount = 1 },
            { name = "polititaske",    amount = 1 }
        }
    },

    -- =========================================
    -- 🕵 Civil Enhed
    -- =========================================
    ["Civil"] = {
        icon  = "fa-solid fa-user-secret",
        image = "civil.png",

        metadata = "Civil loadout med pistol og rustning",

        weapons = {
            "WEAPON_COMBATPISTOL",
            "WEAPON_BZGAS",
            "WEAPON_NIGHTSTICK",
            "WEAPON_FLASHLIGHT"
        },

        items = {
            { name = "policearmour",   amount = 3 },
            { name = "bandage",        amount = 5 },
            { name = "medikit",        amount = 2 },
            { name = "politi-ammo9",   amount = 1 },
            { name = "handcuffs",      amount = 1 },
            { name = "politispikes",   amount = 1 },
            { name = "polititaske",    amount = 1 }
        }
    },

    -- =========================================
    -- 🏍 MC Enhed
    -- =========================================
    ["MC"] = {
        icon  = "fa-solid fa-motorcycle",
        image = "mc.png",

        metadata = "MC-loadout med pistol og rustning",

        weapons = {
            "WEAPON_COMBATPISTOL",
            "WEAPON_BZGAS",
            "WEAPON_NIGHTSTICK",
            "WEAPON_FLASHLIGHT"
        },

        items = {
            { name = "policearmour",   amount = 3 },
            { name = "bandage",        amount = 5 },
            { name = "medikit",        amount = 2 },
            { name = "politi-ammo9",   amount = 1 },
            { name = "handcuffs",      amount = 1 },
            { name = "politispikes",   amount = 1 },
            { name = "polititaske",    amount = 1 }
        }
    },

    -- =========================================
    -- 🛡 AKS Enhed
    -- =========================================
    ["AKS"] = {
        icon  = "fa-solid fa-shield",
        image = "aks.png",

        metadata = "AKS-udstyr: Heavypistol, Carbine Rifle MK2, Rustning",

        weapons = {
            "WEAPON_HEAVYPISTOL",
            "WEAPON_BZGAS",
            "WEAPON_NIGHTSTICK",
            "WEAPON_FLASHLIGHT",
            "WEAPON_CARBINERIFLE_MK2"
        },

        items = {
            { name = "policearmour",   amount = 3 },
            { name = "bandage",        amount = 5 },
            { name = "medikit",        amount = 2 },
            { name = "politi-ammo9",   amount = 1 },
            { name = "politi-ammo3",   amount = 1 },
            { name = "handcuffs",      amount = 1 },
            { name = "politispikes",   amount = 1 },
            { name = "polititaske",    amount = 1 }
        }
    },

    -- =========================================
    -- 📦 Politilager
    -- =========================================
    ["Politilager"] = {
        icon = "fa-solid fa-box-open",

        metadata = "Åbner politiets lager",

        weapons = {},
        items   = {},

        isShop = true,
        shopId = "PoliceArmoury"
    }
}

-- =========================================================
-- 🔹 ATTACHMENTS
-- Hvilke attachments der automatisk sidder på våbnet når loadoutet
-- vælges. Navnene her SKAL matche jeres ox_inventory item-navne
-- (se Politilagerets inventory-liste i server/loadout.lua).
-- Pistoler: kun lommelygte.
-- SMG / Rifler: sigte, forlænget magasin osv.
-- =========================================================

Config.Attachments = {

    -- 🔫 Pistoler
    ["WEAPON_COMBATPISTOL"] = {
        "at_flashlight"
    },
    ["WEAPON_HEAVYPISTOL"] = {
        "at_flashlight"
    },

    -- 🔫 SMG
    ["WEAPON_SMG"] = {
        "small_scope",
        "extended_clip",
        "at_flashlight"
    },

    -- 🔫 Rifler
    ["WEAPON_CARBINERIFLE"] = {
        "medium_scope",
        "extended_clip",
        "at_grip",
        "at_flashlight"
    },
    ["WEAPON_CARBINERIFLE_MK2"] = {
        "large_scope",
        "extended_clip",
        "at_grip",
        "at_flashlight",
        "suppressor",
        "at_barrel",
        "at_skin_camo"
    }
}

-- =========================================================
-- 🔹 JOB BLIPS
-- =========================================================

Config.AllowedJobs = {

    -- =========================================
    -- 👮 POLITI
    -- =========================================
    police = {

        color = 3, -- Blå

        canSee = {
            police   = true,
            ambulance = true
        },

        sprites = {
            default    = 1,
            car        = 56,
            bike       = 859,
            motorcycle = 226,
            boat       = 479,
            helicopter = 574
        }
    },

    -- =========================================
    -- 🚑 AMBULANCE
    -- =========================================
    ambulance = {

        color = 5, -- Gul

        canSee = {
            police    = true,
            ambulance = true
        },

        sprites = {
            default    = 1,
            car        = 56,
            bike       = 859,
            motorcycle = 226,
            boat       = 479,
            helicopter = 574
        }
    },

    -- =========================================
    -- 💰 G6 SECURITY
    -- =========================================
    g6 = {

        color = 2, -- Grøn

        canSee = {
            g6 = true
        },

        sprites = {
            default = 1,
            car     = 56
        }
    },

    -- =========================================
    -- 🔧 MEKANIKER
    -- =========================================
    mechanic = {

        color = 1, -- Rød

        canSee = {
            mechanic = true
        },

        sprites = {
            default = 1,
            car     = 56
        }
    }
}

-- =========================================
-- 🔄 Blip Update Interval
-- =========================================
Config.BlipUpdateInterval = 3000 -- Millisekunder

-- =========================================================
-- 🔹 FEEDBACK SYSTEM
-- =========================================================

-- =========================================
-- ⭐ Feedback Rating Muligheder
-- =========================================
Config.FeedbackChoices = {
    "Ingen feedback endnu",
    "⭐",
    "⭐⭐",
    "⭐⭐⭐",
    "⭐⭐⭐⭐",
    "⭐⭐⭐⭐⭐"
}

-- =========================================
-- 📋 Feedback Kategorier
-- =========================================
Config.FeedbackCategories = {

    {
        label = "Kørsel",
        field = "koersel"
    },

    {
        label = "Brug af radio",
        field = "radio"
    },

    {
        label = "Trafikstop",
        field = "trafik"
    }
}

-- ── STANDARD AMMO/ARMOUR ─────────────────────────────────────
Config.DefaultAmmo   = 500
Config.DefaultArmour = 100

-- =========================================================
-- 🔹 PR. VÅBEN AMMO
-- Bruges af loadout-systemet når et våben gives via
-- ox_inventory. Falder tilbage til Config.DefaultAmmo hvis et
-- våben ikke er nævnt her.
-- =========================================================
Config.WeaponAmmo = {
    ["WEAPON_COMBATPISTOL"]     = 250,
    ["WEAPON_HEAVYPISTOL"]      = 250,
    ["WEAPON_SMG"]              = 300,
    ["WEAPON_CARBINERIFLE"]     = 300,
    ["WEAPON_CARBINERIFLE_MK2"] = 300,
    ["WEAPON_BZGAS"]            = 5,
    ["WEAPON_NIGHTSTICK"]       = 1,
    ["WEAPON_FLASHLIGHT"]       = 1,
    ["WEAPON_STUNGUN"]          = 1,
}

-- ── DEBUG ─────────────────────────────────────────────────────
-- Sat til true viser scriptet ekstra print-output for handcuffs,
-- loadouts, garage, interaction, panic, blips, outfits, evidence
-- og permissions. Ingen console-spam når denne er false.
Config.Debug = false

-- =========================================================
-- 🔹 EVIDENCE STASH
-- =========================================================
Config.EvidenceStash = {
    enabled = true,
    coords  = vec3(448.98, -998.06, 31.67),
    label   = 'Politi Evidence',
    job     = 'police',
    slots   = 100,
    weight  = 4000000, -- gram (ox_inventory bruger gram)
}

-- =========================================================
-- 🔹 OUTFIT LOKATION
-- =========================================================
Config.OutfitLocation = vec3(462.10, -998.92, 30.69)

-- =========================================================
-- 🔹 POLITI OUTFITS
-- Component-numre svarer til FiveM/GTA's ped-component index:
--   torso(11)=jakke/top, pants(4)=bukser, shoes(6)=sko,
--   undershirt(8), arms(3), decals(10) samt props:
--   helmet = hat-prop (0), glasses = briller-prop (1)
-- Sæt et felt til -1 for at rydde den prop/komponent.
-- =========================================================
Config.Outfits = {
    {
        label = 'Patruljeuniform',
        components = {
            torso      = 530,
            pants      = 120,
            shoes      = 25,
            undershirt = 15,
            arms       = 0,
            decals     = 10,
            helmet     = -1,
            glasses    = -1,
        }
    },
    {
        label = 'Trafikuniform',
        components = {
            torso      = 531,
            pants      = 120,
            shoes      = 25,
            undershirt = 15,
            arms       = 0,
            decals     = 10,
            helmet     = -1,
            glasses    = -1,
        }
    },
    {
        label = 'Tactical',
        components = {
            torso      = 55,
            pants      = 121,
            shoes      = 25,
            undershirt = 15,
            arms       = 0,
            decals     = 10,
            helmet     = 35,
            glasses    = 0,
        }
    },
    {
        label = 'Sommeruniform',
        components = {
            torso      = 46,
            pants      = 120,
            shoes      = 25,
            undershirt = 15,
            arms       = 0,
            decals     = 10,
            helmet     = -1,
            glasses    = -1,
        }
    },
    {
        label = 'Vinteruniform',
        components = {
            torso      = 178,
            pants      = 120,
            shoes      = 25,
            undershirt = 15,
            arms       = 0,
            decals     = 10,
            helmet     = -1,
            glasses    = -1,
        }
    },
}