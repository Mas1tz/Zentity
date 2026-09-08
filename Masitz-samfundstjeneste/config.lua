Config = Config or {}

-- ═══════════════════════════════════════════════════════════
--  DEBUG
-- ═══════════════════════════════════════════════════════════
-- Styrer al valgfri debug-output (se Utils.DebugPrint i shared/utils.lua).
-- Skal være 'false' som standard for et rent txAdmin/server-console ved
-- normal drift. Sæt til 'true' midlertidigt for at fejlfinde. Reelle
-- fejl/advarsler (fx databasen ikke klar) printes uanset denne værdi.
Config.Debug = false

Config.Samfundstjeneste = {}

-- ═══════════════════════════════════════════════════════════
--  SITES
-- ═══════════════════════════════════════════════════════════
-- Et "site" er et fysisk arbejdssted med sit eget send-punkt og sin egen
-- anti-escape-zone. Hvert site rummer én eller flere task-typer (se
-- Config.Samfundstjeneste.Tasks nedenfor). At adskille "site" fra "task"
-- betyder at I kan tilføje et helt nyt arbejdssted uden at skulle ændre
-- noget som helst ved de eksisterende steder.
Config.Samfundstjeneste.Sites = {

    boat = {
        label = 'Skibet',

        -- Hvor spilleren sendes hen når tjenesten starter
        sendCoords = vec3(3073.79, -4715.17, 16.09),

        -- Anti-escape: center + radius spilleren ikke må bevæge sig uden for.
        -- 45.0 er bevaret fra V1 (fungerede fint til det tætpakkede dæk).
        antiEscape = {
            center = vec3(3073.79, -4715.17, 16.09),
            radius = 45.0,
        },

        -- Hvilke task-typer (fra Config.Samfundstjeneste.Tasks) der kan
        -- trækkes tilfældigt, når spilleren arbejder på dette site.
        tasks = { 'sweeping' },
    },

    garden = {
        label = 'Haven',

        sendCoords = vec3(5385.15, -5260.79, 34.42),

        -- Radius er sat til 65.0: det fjerneste arbejdspunkt (vandslangen)
        -- ligger ca. 50m fra centrum, så 65 giver samme type bevægelses-
        -- frihed omkring punkterne som V1 havde på skibet. Juster frit her
        -- hvis det føles for stramt/løst i praksis.
        antiEscape = {
            center = vec3(5385.15, -5260.79, 34.42),
            radius = 65.0,
        },

        tasks = { 'gardening' },
    },
}

-- ═══════════════════════════════════════════════════════════
--  MARKER (DrawMarker) — udseende for opgave-punkterne på et site.
--  Bruges af client/tasks.lua. Type 20 = "Number", farven er hex 4C6EF5.
-- ═══════════════════════════════════════════════════════════
Config.Samfundstjeneste.Marker = {
    type = 20,

    color = { r = 0x4C, g = 0x6E, b = 0xF5, a = 180 },

    -- Størrelse (x/y/z) på selve markøren.
    size = vec3(0.3, 0.3, 0.3),

    -- Hvor højt over selve punktet markøren tegnes.
    heightOffset = 1.0,

    -- Hvor langt væk (meter) markørerne begynder at blive tegnet. Sat højt
    -- nok til at spilleren kan se ALLE opgavepunkter på sitet på én gang,
    -- ikke kun det de allerede står ved.
    drawDistance = 60.0,
}

-- Fælles løsladelses-punkt for alle sites, medmindre et site definerer sit
-- eget (se releaseCoords-override-mulighed nedenfor hvis det bliver nødvendigt).
Config.Samfundstjeneste.General = {
    releaseCoords = vec3(435.44, -974.57, 30.72),
}

-- ═══════════════════════════════════════════════════════════
--  PERMISSIONS
-- ═══════════════════════════════════════════════════════════
-- ESX-grupper der regnes som "Staff". Owner er IKKE en ESX-gruppe, men
-- bestemmes af Discord-ID'et nedenfor (se server/permissions.lua) — det er
-- bevidst adskilt fra grupper, da du kun vil have ÉN person som owner.
Config.Samfundstjeneste.Permissions = {
    StaffGroups = {
        admin = true,
        superadmin = true,
    },

    -- Din Discord-ID. Behandles som Owner uanset ESX-gruppe.
    -- Arkitekturen i server/permissions.lua er bygget så dette ene felt er
    -- det eneste der skal ændres, den dag du kobler jeres eget Discord-
    -- auth-system på i stedet.
    OwnerDiscordId = '1529563765870301217',
}

-- ═══════════════════════════════════════════════════════════
--  COMMANDS
-- ═══════════════════════════════════════════════════════════
-- Alle disse kommando-navne åbner det samme dashboard. Tilføj/fjern
-- aliaser her uden at skulle røre nogen andre filer.
Config.Samfundstjeneste.Commands = {
    'sf',
    'samfundstjeneste',
}

-- ═══════════════════════════════════════════════════════════
--  TRUST FACTOR
-- ═══════════════════════════════════════════════════════════
-- Alle spillere starter på 100% (sat af databasen som DEFAULT). Tab sker
-- automatisk hver gang der GIVES opgaver (Staff-handling eller /kommando),
-- ikke ved automatisk tidsreduktion eller almindelig completion.
--
-- mode = 'per_task'    → hver enkelt tildelt opgave koster perTask.loss %
-- mode = 'per_x_tasks' → for hver perXTasks.tasks tildelte opgaver mistes
--                        perXTasks.loss % (afrundes ned til nærmeste hele
--                        "blok" — 9 opgaver ved tasks=10 giver ikke tab endnu)
Config.Samfundstjeneste.TrustFactor = {
    enabled = true,
    mode = 'per_x_tasks', -- 'per_task' | 'per_x_tasks'

    perTask = {
        loss = 0.5,
    },

    perXTasks = {
        tasks = 10,
        loss = 2.0,
    },

    -- Recovery kræver REEL aktiv server-tilstedeværelse (se AFK-system i
    -- client/activity.lua + server/trustfactor.lua). AFK tid tæller ikke.
    recovery = {
        enabled = true,
        requiredActiveMinutes = 60,
        recoveryAmount = 1.0,

        -- Ingen bevægelse/input i dette antal sekunder = spilleren regnes
        -- som AFK, og recovery-timeren stopper indtil de er aktive igen.
        afkTimeoutSeconds = 120,
    },
}

-- ═══════════════════════════════════════════════════════════
--  AUTOMATISK TIDSREDUKTION
-- ═══════════════════════════════════════════════════════════
-- Mens en spiller er aktivt i gang med tjenesten (dvs. sendt til et site),
-- fjernes "amount" opgave(r) hvert "interval" sekund. Sættes på pause af
-- anti-escape (se nedenfor) — men fjerner ALDRIG opgaver i sig selv.
Config.Samfundstjeneste.TimeReduction = {
    enabled = true,
    interval = 30,
    amount = 1,
}

-- ═══════════════════════════════════════════════════════════
--  ANTI-REPEAT
-- ═══════════════════════════════════════════════════════════
-- Forhindrer at spilleren kan blive stående ét sted og få den samme
-- opgave-placering igen og igen (AFK-farming). Ved hvert nyt opgavevalg
-- udelukkes de "avoidLastPoints" senest brugte arbejdspunkter fra puljen,
-- hvis der er nok punkter til at det stadig er muligt. Har et site/en
-- task-type så få punkter at det ikke kan lade sig gøre, bruges hele
-- puljen i stedet for at fejle. Rent server-side (se server/tasks.lua)
-- — klienten har ingen indflydelse på hvilket punkt der vælges.
Config.Samfundstjeneste.AntiRepeat = {
    avoidLastPoints = 2,
}

-- ═══════════════════════════════════════════════════════════
--  ANTI-ESCAPE
-- ═══════════════════════════════════════════════════════════
-- Zonen for hvert enkelt site defineres på selve sitet
-- (Config.Samfundstjeneste.Sites[x].antiEscape.center/radius). Dette er de
-- GLOBALE regler for hvad der sker når en spiller krydser den zone.
Config.Samfundstjeneste.AntiEscape = {
    enabled = true,

    -- Hvor ofte (ms) klienten tjekker afstand til sitets center.
    checkInterval = 2000,

    -- Hvor længe (sekunder) automatisk tidsreduktion sættes på pause efter
    -- et flugtforsøg. Opgaver fjernes IKKE i denne periode.
    taskPauseDuration = 300,
}

-- ═══════════════════════════════════════════════════════════
--  IDENTITY / STEAM
-- ═══════════════════════════════════════════════════════════
-- Steam Web API-nøglen ligger BEVIDST ikke her, da config.lua er en
-- shared_script og derfor sendes til alle klienter. Nøglen læses
-- udelukkende server-side via en convar (se server/identity.lua):
--
--   set steam_webApiKey "din-nøgle-her"
--
-- Tilføj den linje til server.cfg (før "ensure Masitz-samfundstjeneste").
Config.Samfundstjeneste.Identity = {
    steamEnabled = true,
    -- Hvor tit (minutter) et allerede-cachet Steam-avatar/navn må genbruges
    -- før det opdateres igen fra Steam Web API.
    steamCacheMinutes = 60,
}

-- ═══════════════════════════════════════════════════════════
--  TASKS
-- ═══════════════════════════════════════════════════════════
-- Hver task definerer sin egen animation, varighed og arbejdspunkter.
-- "points" bruges til at vælge et TILFÆLDIGT punkt hver gang en ny opgave
-- skal udføres (præcis som V1's taskPoints, bare genbrugeligt pr. task-type).
--
-- animation.type = 'emote'
--   command  = ét fast emote-kommando (fx 'e mechanic3')
--   random   = { 'e hoe', 'e hoe2', ... } -- ét trækkes tilfældigt hver gang
--
-- (Kun ÉT af 'command' eller 'random' skal udfyldes pr. task.)
Config.Samfundstjeneste.Tasks = {

    sweeping = {
        label = 'Fej dækket',
        description = 'Fej dækket rent.',
        enabled = true,

        duration = { min = 5000, max = 15000 },

        animation = {
            type = 'emote',
            command = 'e broom',
        },

        points = {
            vec3(3071.04, -4718.57, 15.6),
            vec3(3076.54, -4712.92, 15.6),
            vec3(3068.51, -4711.23, 15.6),
            vec3(3076.12, -4719.85, 15.6),
            vec3(3072.45, -4714.50, 15.6),
        },
    },

    gardening = {
        label = 'Fjern ukrudt',
        description = 'Fjern ukrudtet fra bedet.',
        enabled = true,

        duration = { min = 5000, max = 15000 },

        animation = {
            type = 'emote',
            -- Ét af disse trækkes tilfældigt hver gang opgaven startes.
            -- 'e mechanic3' er den gamle "Reparér vandslangen"-animation,
            -- flyttet herind da den opgave blev lagt sammen med "Fjern ukrudt".
            random = { 'e hoe', 'e hoe2', 'e hoe3', 'e hoe4', 'e mechanic3' },
        },

        points = {
            vec3(5387.04, -5269.60, 34.92),
            vec3(5380.04, -5290.29, 35.63),
            vec3(5367.86, -5280.53, 34.69),
            vec3(5343.96, -5248.50, 32.42),
            vec3(5352.12, -5248.36, 32.70),
            vec3(5363.42, -5251.34, 33.03),
            vec3(5374.68, -5240.95, 33.15),
            vec3(5370.25, -5224.10, 31.86),
            -- Tidligere "waterhose"-punktet, nu en del af "Fjern ukrudt".
            vec3(5336.14, -5250.48, 32.60),
        },
    },
}
