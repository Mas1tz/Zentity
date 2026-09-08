-- ============================================================
--  config.lua  –  Faktura Tablet V2
-- ============================================================

Config = {}

-- Framework: "auto", "esx", "qb"
Config.Framework = "auto"

Config.PropPlacement = {-0.05, 0.0, 0.0, 0.0, -90.0, 0.0}

-- ============================================================
--  JOBS der må ÅBNE tabletten og sende regninger
-- ============================================================
Config.BillingJobs = {
    mechanic  = { label = "Mekaniker",        access = true },
    police    = { label = "Politi",           access = true },
    ambulance = { label = "Ambulance",        access = true },
    taxi      = { label = "Taxi",             access = true },
    cardealer = { label = "Bilforhandler",    access = true },
    advokat   = { label = "Advokat",          access = true },
    unicorn   = { label = "Vanilla Unicorn",  access = true },
    burgershot = { label = "Burgershot",       access = true },
}

-- Rabat-trin man kan vælge når man sender en regning
Config.Discounts = { 0, 5, 10, 15, 25 }

-- Hvor mange dage en regning (betalt ELLER ubetalt) må ligge før den auto-slettes
Config.InvoiceRetentionDays = 7

-- ============================================================
--  HVEM MÅ OPRETTE/REDIGERE/SLETTE KATEGORIER I TABLETTEN?
--  - aceGroup: fuld adgang til ALLE jobs' kategorier (typisk sat af en
--    discord-rolle-bot der tildeler ACE-grupper, fx via `add_principal`)
--  - jobGradeOverride: spillere med mindst denne grad i DERES EGET job
--    må redigere kategorierne for netop det job (og intet andet)
-- ============================================================
Config.CategoryManagement = {
    aceGroup = "faktura.admin",
    -- Nemt alternativ til ACE mens du tester: put dine egne identifiers her
    -- (fx "license:abc123..."), så får du fuld adgang til ALLE jobs' kategorier
    -- uden at skulle sætte ACE-grupper op i server.cfg.
    superAdmins = {
        -- "license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    },
    jobGradeOverride = {
        mechanic  = 3,
        police    = 3,
        ambulance = 3,
        taxi      = 3,
        cardealer = 3,
        advokat   = 3,
        unicorn   = 3,
        burgershot = 5,
    },
}

-- ============================================================
--  TABLET UI OPTIONS (sendes til NUI)
-- ============================================================
Config.Tablet = {
    title    = "Faktura Tablet",
    logoText = "FT",
    accent1  = "#ff3b5c",
    accent2  = "#7a5cff",
    themeBg  = "#161616",
}

-- ============================================================
--  KATEGORIER (grupperet pr. job)
--  Struktur: Config.Categories.<job> = { { group = "...", items = { {id,label,price}, ... } }, ... }
--  Dette er kun "grund-kataloget". Andre resources kan tilføje flere
--  grupper/varer via export uden at røre denne fil, og spillere med
--  rettigheder kan tilføje endnu flere direkte i tabletten (gemmes i DB).
-- ============================================================
Config.Categories = {

    mechanic = {
        {
            group = "Standard Service",
            items = {
                { id = "service",    label = "Service eftersyn",        price = 500 },
                { id = "olie_skift", label = "Olieskift",                price = 650 },
                { id = "syn",        label = "Klargøring til syn",       price = 1500 },
                { id = "vask",       label = "Bilvask (Håndvask)",       price = 250 },
            },
        },
        {
            group = "Reparationer – Motor & Drivlinje",
            items = {
                { id = "motor_repair",         label = "Reparation af motor",              price = 3500 },
                { id = "transmission_repair",  label = "Reparation af gearkasse",          price = 2800 },
                { id = "turbo_repair",         label = "Reparation/Udskift af turbo",      price = 4000 },
                { id = "udstodning_repair",    label = "Reparation af udstødning",         price = 1200 },
            },
        },
        {
            group = "Reparationer – Karrosseri & Skade",
            items = {
                { id = "rust_repair", label = "Reparation af rust",         price = 2000 },
                { id = "bule_lille",  label = "Opkretning af lille bule",   price = 800 },
                { id = "bule_stor",   label = "Opkretning af stor skade",   price = 2500 },
                { id = "rude_skift",  label = "Udskiftning af ruder",       price = 1300 },
            },
        },
        {
            group = "Hjul & Bremser",
            items = {
                { id = "daek_skift",    label = "Dækskifte (Alle 4)",                    price = 700 },
                { id = "bremse_skift",  label = "Udskiftning af bremser (Hele sættet)",  price = 2200 },
                { id = "bremse_check",  label = "Bremsetjek & justering",                price = 450 },
            },
        },
        {
            group = "Tuning",
            items = {
                { id = "tuning_motor_1",    label = "Motoroptimering (Stage 1)",      price = 5000 },
                { id = "tuning_bremser_1",  label = "Bremseopgradering (Sport)",      price = 3000 },
                { id = "tuning_turbo",      label = "Installation af Turbo",          price = 7500 },
            },
        },
    },

    police = {
        {
            group = "Færdselsloven",
            items = {
                { id = "kontrolgebyr",   label = "Kontrolafgift (Parkering)",              price = 500 },
                { id = "parkering_fejl", label = "Fejlparkering (Til gene)",               price = 750 },
                { id = "glemt_sele",     label = "Kørsel uden sikkerhedssele",             price = 1000 },
                { id = "trafikboede",    label = "Standard Trafikbøde (Lille)",            price = 1500 },
                { id = "mobil_koersel",  label = "Håndholdt mobil under kørsel",           price = 2000 },
                { id = "defekt_koeretoej", label = "Kørsel i defekt køretøj",               price = 1000 },
                { id = "roedt_lys",      label = "Kørsel over for rødt lys",               price = 2500 },
                { id = "hastighed_1",    label = "Hastighedsoverskridelse (Lille)",        price = 2000 },
                { id = "hastighed_2",    label = "Hastighedsoverskridelse (Stor)",         price = 3500 },
                { id = "hastighed_3",    label = "Vanvidskørsel (Hastighed)",              price = 6000 },
                { id = "uden_koerekort", label = "Kørsel uden førerret",                   price = 5000 },
                { id = "spiritus",       label = "Spirituskørsel",                         price = 7500 },
            },
        },
        {
            group = "Offentlig Orden",
            items = {
                { id = "gadeuorden",       label = "Gadeuorden (Råb, larm)",         price = 1500 },
                { id = "tisse_offentligt", label = "Urinering på offentligt sted",   price = 1000 },
                { id = "maskering",        label = "Maskering på offentlig vej",     price = 2000 },
                { id = "falsk_alarm",      label = "Falsk alarmopkald (112)",        price = 3000 },
            },
        },
        {
            group = "Straffeloven – Personfarlig",
            items = {
                { id = "boede_vold",         label = "Simpel Vold",           price = 5000 },
                { id = "boede_vold_grovere", label = "Grovere Vold",          price = 8000 },
                { id = "trusler",            label = "Trusler (Verbale)",     price = 4000 },
                { id = "trusler_livet",      label = "Trusler på livet",      price = 7000 },
            },
        },
        {
            group = "Straffeloven – Ejendom & Økonomi",
            items = {
                { id = "tyveri_lille", label = "Simpelt Tyveri",              price = 2500 },
                { id = "tyveri_stort", label = "Større Tyveri",               price = 6000 },
                { id = "haervaerk",    label = "Hærværk",                     price = 4500 },
                { id = "indbrud",      label = "Indbrud (Forsøg/Fuldført)",   price = 7000 },
            },
        },
        {
            group = "Våbenloven & Narko",
            items = {
                { id = "narko_besiddelse", label = "Besiddelse af euforiserende stoffer",  price = 4000 },
                { id = "narko_salg",       label = "Salg af euforiserende stoffer",        price = 10000 },
                { id = "vaaben_kniv",      label = "Ulovlig besiddelse af kniv",           price = 7000 },
                { id = "vaaben_pistol",    label = "Ulovlig besiddelse af skydevåben",     price = 15000 },
            },
        },
    },

    ambulance = {
        { group = "Ambulance", items = {
            { id = "ambulance_fee", label = "Ambulance udrykning", price = 2500 },
            { id = "saarpleje",     label = "Sårpleje",            price = 800 },
        } },
    },

    taxi = {
        { group = "Taxi", items = {
            { id = "taxi_fee", label = "Taxitur", price = 300 },
        } },
    },

    cardealer = {
        { group = "Bilforhandler", items = {
            { id = "service",  label = "Service",        price = 1000 },
            { id = "salg_fee", label = "Salgshonorar",   price = 500 },
        } },
    },

    advokat = {
        { group = "Advokat", items = {
            { id = "retssag",  label = "Retsrådgivning",         price = 4000 },
            { id = "dokument", label = "Dokumentudarbejdelse",   price = 1000 },
        } },
    },

    unicorn = {
        { group = "Cocktails", items = {
            { id = "whiskey",             label = "Whiskey",           price = 350 },
            { id = "vodka",                label = "Vodka",             price = 250 },
            { id = "rum",                  label = "Rom",               price = 275 },
            { id = "gin",                  label = "Gin",               price = 300 },
            { id = "tequila",              label = "Tequila",           price = 350 },
            { id = "cocktail_mojito",      label = "Mojito",            price = 450 },
            { id = "cocktail_margarita",   label = "Margarita",         price = 400 },
        } },
        { group = "Whiskey-relaterede", items = {
            { id = "whiskey_sour",   label = "Whiskey Sour",   price = 500 },
            { id = "bourbon",        label = "Bourbon",        price = 550 },
            { id = "irish_whiskey",  label = "Irish Whiskey",  price = 600 },
            { id = "scotch",         label = "Scotch",         price = 650 },
        } },
        { group = "Champagne & Special", items = {
            { id = "champagne",       label = "Champagne",        price = 2000 },
            { id = "sparkling_wine",  label = "Sparkling Wine",   price = 1800 },
            { id = "cosmopolitan",    label = "Cosmopolitan",     price = 500 },
            { id = "old_fashioned",   label = "Old Fashioned",    price = 600 },
        } },
    },

    burgershot = {
        { group = "Burgers", items = {
            { id = "burger-bleeder",      label = "Bleeder Burger",      price = 145 },
            { id = "burger-moneyshot",    label = "Money Shot Burger",   price = 175 },
            { id = "burger-meatfree",     label = "Meat Free Burger",    price = 155 },
            { id = "burger-heartstopper", label = "Heart Stopper",       price = 225 },
        } },

        { group = "Sides", items = {
            { id = "burger-fries",        label = "French Fries",        price = 65 },
            { id = "burger-torpedo",      label = "Chicken Torpedo",     price = 95 },
        } },

        { group = "Drinks & Desserts", items = {
            { id = "burger-softdrink",    label = "Soft Drink",          price = 45 },
            { id = "burger-milk",         label = "Milk",                price = 35 },
            { id = "burger-mshake",       label = "Milkshake",           price = 75 },
        } },
    },
}
