-- ============================================================
--  kc_mdt | config.lua
--  Dansk Politi-MDT · ESX Legacy · ox_lib · oxmysql
--
--  ALT hvad du typisk skal justere ligger i DENNE fil.
--  Du behøver IKKE at røre HTML/CSS/JS eller Lua for at:
--    - Tilføje/fjerne/redigere en menu (Config.Menus)
--    - Tilføje/fjerne/redigere en lov (Config.Laws)
--    - Tilføje/fjerne/redigere en radiomelding (Config.RadioCodes)
--    - Tilføje/fjerne/redigere en bøde (Config.Fines)
--  Genstart blot resourcen efter en ændring.
-- ============================================================

Config = {}

-- ─── ADGANG ──────────────────────────────────────────────────
Config.AllowedJobs = {
    ['police']  = true,
    ['sheriff'] = true,
    ['state']   = true,
}

-- ─── PERMISSIONS PR. HANDLING ────────────────────────────────
Config.Permissions = {
    createAccount     = 10,
    resetPassword     = 10,
    deactivateAccount = 10,
    issueWarrant      = 3,
    removeWarrant     = 5,
    createArrest      = 1,
    closeCase         = 5,
    deleteJournal      = 6,
    flagVehicle       = 3,
    createDispatch    = 1,
    resolveDispatch   = 1,
}

-- ─── KOMMANDOER & KEYBINDS ───────────────────────────────────
Config.Command         = 'mdt'
Config.Keybind         = 'K'
Config.RegisterCommand = 'registermdt'

-- ─── /REGISTERMDT INDSTILLINGER ──────────────────────────────
Config.RegisterMDT = {
    nearestRadius   = 30.0,
    nearestMaxShown = 8,
    defaultPassword = '1234',
    forcePwChange   = true,
    cooldownSec     = 5,
    badgePrefix     = 'BADGE-',
}

-- ─── PASSWORD / SECURITY ─────────────────────────────────────
-- VIGTIGT: Skift denne pepper ved første install. Skift den ALDRIG igen,
-- ellers mister alle konti deres password.
Config.PasswordPepper = 'CHANGE_ME_BEFORE_PRODUCTION_xK9mPq2Lz8vWnTjR'

Config.Security = {
    loginMaxAttempts  = 5,
    loginLockoutMin   = 10,
    sessionTimeoutMin = 60,
    minUsernameLen    = 3,
    maxUsernameLen    = 24,
    minPasswordLen    = 4,
    maxPasswordLen    = 64,
    usernamePattern   = '^[%w%._%-]+$',
}

-- ─── PROP & ANIMATION ────────────────────────────────────────
Config.PropModel  = `prop_cs_tablet`
Config.PropBone   = 28422
Config.PropOffset = { x = -0.05, y = 0.0,   z = 0.0  }
Config.PropRot    = { x =  0.0,  y = -90.0, z = 0.0  }
Config.AnimDict   = 'amb@code_human_in_bus_passenger_idles@female@tablet@base'
Config.AnimName   = 'base'
Config.AnimBlend  = 3.0

-- ─── FLÅDESTYRING — ENHEDSTYPER ──────────────────────────────
Config.PatrolUnits = {
    { call = 'ROMEO-1',   label = 'Romeo · Reaktionspatrulje',   type = 'car'     },
    { call = 'ROMEO-2',   label = 'Romeo · Reaktionspatrulje 2', type = 'car'     },
    { call = 'MIKE-1',    label = 'Mike · Motorcykel',           type = 'moto'    },
    { call = 'CHARLIE-1', label = 'Charlie · Civilpatrulje',     type = 'car'     },
    { call = 'KILO-1',    label = 'Kilo · Trafik',               type = 'car'     },
    { call = 'FOX-1',     label = 'Fox · Helikopter',            type = 'heli'    },
    { call = 'LIMA-1',    label = 'Lima · Indsatsleder',         type = 'command' },
    { call = 'SIERRA-1',  label = 'Sierra · Specialenhed',       type = 'swat'    },
    { call = 'TANGO-1',   label = 'Tango · Tungvogn',            type = 'car'     },
    { call = 'ATK-1',     label = 'ATK · Anholdelse',            type = 'car'     },
}

-- ─── SYNC INTERVALLER ────────────────────────────────────────
Config.GPSSyncInterval   = 8000
Config.GPSWriteThreshold = 15.0
Config.PatrolCleanupSec  = 90

-- ─── RISIKONIVEAUER (bruges på Efterlysning/Sigtelse) ────────
Config.RiskLevels = {
    [0] = { label = 'Ingen',   color = '#6b7280' },
    [1] = { label = 'Lav',     color = '#22c55e' },
    [2] = { label = 'Moderat', color = '#f59e0b' },
    [3] = { label = 'Høj',     color = '#ef4444' },
    [4] = { label = 'Ekstrem', color = '#7c3aed' },
}

-- ─── BESLAGLAGTE GENSTANDE — KATEGORIER (§19) ─────────────────
-- Bruges som forslag/dropdown når en betjent tilføjer en beslaglagt
-- genstand til en sigtelse. Tilføj/fjern/redigér frit.
Config.SeizedCategories = {
    'Våben', 'Slagvåben', 'Stoffer', 'Kontanter', 'Telefon', 'Køretøj', 'Andre genstande',
}

-- ─── BILLEDER (efterlysning/sigtelse — CTRL+V, §12/§18) ───────
-- Billeder indsat med CTRL+V bliver komprimeret/skaleret client-side
-- (Canvas) før de sendes til serveren, så vi undgår at gemme unødvendigt
-- store billeder i databasen.
Config.Images = {
    maxDimensionPx = 640,   -- billedet skaleres ned så længste side maks er dette
    jpegQuality    = 0.72,  -- 0.0–1.0
    maxPerEntry    = 4,     -- maks antal billeder pr. sigtelse (efterlysning har altid kun 1)
}

-- ─── ANTI-SPAM ───────────────────────────────────────────────
Config.SpamThrottleMS = 600

-- ─── DEBUG ───────────────────────────────────────────────────
Config.Debug = false


-- ============================================================
--  UI — OPACITY, FARVER OG ANDRE VISUELLE INDSTILLINGER
--  (redigér frit — bruges direkte af NUI'en)
-- ============================================================
Config.UI = {
    defaultOpacity = 1.00,   -- 100% som standard (§2)
    minOpacity     = 0.10,   -- laveste værdi slideren kan sættes til
    hoverOpacity   = 0.50,   -- opacity når musen er over søgefeltet (§1)
    opacitySteps   = { 1.00, 0.90, 0.80, 0.70, 0.60, 0.50, 0.40, 0.30, 0.20, 0.10 },

    -- Farvetema: lys sort/mørkegrå base + blå accent (§41).
    -- Sendes til NUI'en og sættes som CSS-variabler ved opstart,
    -- så paletten kan ændres ét sted uden at røre style.css.
    Theme = {
        bgPrimary     = '#16181d',
        bgSecondary   = '#1c1f26',
        bgCard        = '#20232b',
        bgHover       = '#262a33',
        accentBlue    = '#3b82f6',
        accentBlueHov = '#2563eb',
        textPrimary   = '#f1f2f4',
        textSecondary = '#a7acb8',
        textMuted     = '#6b7280',
        borderColor   = '#2c303a',
    },
}


-- ============================================================
--  MENUER — VENSTRE NAVIGATION (§3, §4)
--
--  Tilføj/fjern/redigér en menu ved blot at tilføje/fjerne/ændre
--  et element i denne liste. Rækkefølgen i listen = rækkefølgen
--  i navigationen.
--
--  Felter:
--    id          -> skal matche et "tab" i NUI'en
--    label       -> tekst i navigationen
--    icon        -> ikon-nøgle (frontendens ikon-sæt)
--    enabled     -> false = menuen vises slet ikke
--    development -> true  = vises men markeret "Under udvikling" (bruges
--                    pt. til Dispatch, §9) og kan ikke åbnes endnu
-- ============================================================
Config.Menus = {
    { id = 'dashboard', label = 'Dashboard',       icon = 'home',     enabled = true },
    { id = 'persons',   label = 'Personregister',  icon = 'users',    enabled = true },
    { id = 'vehicles',  label = 'Køretøjer',       icon = 'car',      enabled = true },
    { id = 'warrants',  label = 'Efterlysninger',  icon = 'alert',    enabled = true },
    { id = 'cases',     label = 'Sigtelser',       icon = 'file',     enabled = true },
    { id = 'patrol',    label = 'Flådestyring',    icon = 'shield',   enabled = true },
    { id = 'dispatch',  label = 'Dispatch',        icon = 'radio',    enabled = true, development = true },
    { id = 'laws',      label = 'Lovbog',          icon = 'book',     enabled = true },
    { id = 'charges',   label = 'Bødeskema',       icon = 'gavel',    enabled = true },
    { id = 'accounts',  label = 'Konti',           icon = 'key',      enabled = true },
    { id = 'settings',  label = 'Indstillinger',   icon = 'settings', enabled = true },
    -- Sådan tilføjer du selv en ny menu senere:
    -- { id = 'mynye', label = 'Min Nye Menu', icon = 'star', enabled = true },
}


-- ============================================================
--  DANSKE RADIOMELDINGER (§6)
--  Erstatter de tidligere amerikanske 10-koder.
--  Tilføj/fjern/redigér frit — vises i Lovbogen under "Radiomeldinger".
-- ============================================================
Config.RadioCodes = {
    { code = 'Kvittering',                  desc = 'Beskeden er modtaget og forstået' },
    { code = 'Fri',                         desc = 'Kanalen/enheden er ledig igen' },
    { code = 'Optaget',                     desc = 'Enheden er midlertidigt optaget' },
    { code = 'I tjeneste',                  desc = 'Betjenten er klar til udkald' },
    { code = 'Ude af tjeneste',             desc = 'Betjenten er ikke tilgængelig' },
    { code = 'På vej',                      desc = 'Enheden kører mod adressen/opgaven' },
    { code = 'Fremme',                      desc = 'Enheden er ankommet på stedet' },
    { code = 'Anholdelse foretaget',        desc = 'En person er anholdt/tilbageholdt' },
    { code = 'Efterlysning bekræftet',      desc = 'Personen er aktivt efterlyst' },
    { code = 'Assistance ønskes',           desc = 'Der ønskes flere enheder til stedet' },
    { code = 'Ambulance ønskes',            desc = 'Der er behov for sundhedsfagligt personale' },
    { code = 'Brand',                       desc = 'Der er observeret brand — brandvæsen kontaktes' },
    { code = 'Kollega har brug for hjælp',  desc = 'Prioritet 1 — alle ledige enheder rykker ud' },
    { code = 'Nødsituation',                desc = 'PANIC — akut fare for liv' },
    -- Sådan tilføjer du selv en ny radiomelding:
    -- { code = 'Min nye kode', desc = 'Beskrivelse af hvad den betyder' },
}


-- ============================================================
--  LOVBOG (§5)
--  Struktureret i kategorier. Tilføj en ny kategori ved at
--  tilføje en ny nøgle, eller tilføj/redigér enkelte love i en
--  eksisterende kategori.
--
--  Felter pr. lov:
--    paragraph -> paragraf-nummer/reference
--    title     -> kort titel
--    text      -> fuld beskrivelse
-- ============================================================
Config.Laws = {
    faerdsel = {
        book = 'Færdselsloven',
        entries = {
            { paragraph = '§ 4',   title = 'Hastighedsoverskridelse', text = 'Kørsel med højere hastighed end det skiltede/gældende for vejen.' },
            { paragraph = '§ 42',  title = 'Uforsvarlig kørsel',      text = 'Kørsel der er til fare eller ulempe for andre trafikanter.' },
            { paragraph = '§ 53',  title = 'Spirituskørsel',          text = 'Kørsel med en promille over den lovlige grænse.' },
            { paragraph = '§ 56',  title = 'Kørsel uden kørekort',    text = 'Kørsel af køretøj uden gyldigt kørekort til køretøjstypen.' },
            { paragraph = '§ 118', title = 'Flugt fra politiet',      text = 'Undladelse af at standse for politiets tegn til stop under kørsel.' },
        },
    },
    koeretoejer = {
        book = 'Køretøjsloven',
        entries = {
            { paragraph = '§ 7',  title = 'Ulovlig registrering',  text = 'Kørsel med afmonteret, forfalsket eller ulæselig nummerplade.' },
            { paragraph = '§ 10', title = 'Uforsikret køretøj',    text = 'Kørsel med et køretøj uden gyldig ansvarsforsikring.' },
            { paragraph = '§ 15', title = 'Manglende syn',         text = 'Kørsel med et køretøj uden gyldigt synsresultat.' },
            { paragraph = '§ 22', title = 'Ombygget/ulovligt køretøj', text = 'Væsentlige, ikke-godkendte ændringer på køretøjet.' },
        },
    },
    personforhold = {
        book = 'Straffeloven — Personfarlig kriminalitet',
        entries = {
            { paragraph = '§ 244', title = 'Vold',                text = 'Legemlig vold mod en anden person.' },
            { paragraph = '§ 245', title = 'Grov vold',            text = 'Vold af særlig rå, brutal eller farlig karakter.' },
            { paragraph = '§ 260', title = 'Ulovlig tvang',        text = 'Tvinge en person til at gøre, tåle eller undlade noget.' },
            { paragraph = '§ 261', title = 'Frihedsberøvelse',     text = 'Ulovlig berøvelse af en persons frihed.' },
            { paragraph = '§ 266', title = 'Trusler',              text = 'Fremsætte trusler om strafbart forhold.' },
        },
    },
    vaaben = {
        book = 'Våbenloven',
        entries = {
            { paragraph = '§ 1', title = 'Ulovlig våbenbesiddelse',           text = 'Besiddelse af skydevåben uden gyldig våbentilladelse.' },
            { paragraph = '§ 2', title = 'Besiddelse af stik-/slagvåben',     text = 'Besiddelse af kniv eller slagvåben uden lovligt formål.' },
            { paragraph = '§ 4', title = 'Bæren af våben på offentligt sted', text = 'Fremvisning/bæren af våben på offentligt tilgængeligt sted.' },
        },
    },
    stoffer = {
        book = 'Lov om euforiserende stoffer',
        entries = {
            { paragraph = '§ 3, stk. 1', title = 'Besiddelse til eget brug',    text = 'Besiddelse af euforiserende stoffer til eget forbrug.' },
            { paragraph = '§ 3, stk. 2', title = 'Besiddelse med salgshensigt', text = 'Besiddelse af euforiserende stoffer med henblik på videresalg.' },
            { paragraph = '§ 4',         title = 'Handel med euforiserende stoffer', text = 'Salg eller distribution af euforiserende stoffer.' },
        },
    },
    roeveri = {
        book = 'Straffeloven — Formueforbrydelser',
        entries = {
            { paragraph = '§ 276', title = 'Tyveri',    text = 'Fratage en anden en genstand med henblik på uberettiget vinding.' },
            { paragraph = '§ 279', title = 'Bedrageri',  text = 'Skaffe sig eller andre uberettiget vinding ved brug af svig.' },
            { paragraph = '§ 288', title = 'Røveri',     text = 'Tyveri ved brug af eller trussel om vold.' },
        },
    },
    -- Sådan tilføjer du selv en ny lov-kategori:
    -- minnyekategori = {
    --     book = 'Titel på lovbog',
    --     entries = {
    --         { paragraph = '§ 1', title = '...', text = '...' },
    --     },
    -- },
}


-- ============================================================
--  BØDESKEMA (§7)
--  Struktureret i kategorier, ligesom Lovbogen.
--
--  Felter pr. bøde:
--    label  -> navn på forseelsen
--    fine   -> bødebeløb (tal, ingen tekst/valuta)
--    jail   -> evt. fængselstid i minutter (0 = ingen)
--    lawRef -> valgfri tekst-reference til en paragraf i Config.Laws
-- ============================================================
Config.Fines = {
    hastigheder = {
        { label = 'Hastighedsoverskridelse 1-20 km/t', fine = 1500,  jail = 0,  lawRef = 'Færdselsloven § 4' },
        { label = 'Hastighedsoverskridelse 21-40 km/t', fine = 3500,  jail = 0,  lawRef = 'Færdselsloven § 4' },
        { label = 'Hastighedsoverskridelse 41+ km/t',   fine = 6000,  jail = 5,  lawRef = 'Færdselsloven § 4' },
    },
    faerdsel = {
        { label = 'Uforsvarlig kørsel',       fine = 2500,  jail = 5,  lawRef = 'Færdselsloven § 42' },
        { label = 'Spirituskørsel',           fine = 8000,  jail = 15, lawRef = 'Færdselsloven § 53' },
        { label = 'Kørsel uden kørekort',     fine = 4000,  jail = 0,  lawRef = 'Færdselsloven § 56' },
        { label = 'Flugt fra politiet',       fine = 10000, jail = 20, lawRef = 'Færdselsloven § 118' },
        { label = 'Uforsikret/usynet køretøj', fine = 2000, jail = 0,  lawRef = 'Køretøjsloven § 10' },
    },
    vaaben = {
        { label = 'Ulovlig besiddelse af skydevåben',        fine = 12000, jail = 25, lawRef = 'Våbenloven § 1' },
        { label = 'Besiddelse af stik-/slagvåben',            fine = 3000,  jail = 5,  lawRef = 'Våbenloven § 2' },
        { label = 'Fremvisning af våben på offentligt sted',  fine = 5000,  jail = 10, lawRef = 'Våbenloven § 4' },
    },
    stoffer = {
        { label = 'Besiddelse til eget brug',        fine = 1500,  jail = 5,  lawRef = 'Stofloven § 3, stk. 1' },
        { label = 'Besiddelse med salgshensigt',      fine = 7000,  jail = 15, lawRef = 'Stofloven § 3, stk. 2' },
        { label = 'Handel med euforiserende stoffer', fine = 15000, jail = 30, lawRef = 'Stofloven § 4' },
    },
    roeverier = {
        { label = 'Tyveri',    fine = 3000,  jail = 10, lawRef = 'Straffeloven § 276' },
        { label = 'Bedrageri', fine = 4000,  jail = 10, lawRef = 'Straffeloven § 279' },
        { label = 'Røveri',    fine = 12000, jail = 25, lawRef = 'Straffeloven § 288' },
    },
    vold = {
        { label = 'Vold',               fine = 5000,  jail = 15, lawRef = 'Straffeloven § 244' },
        { label = 'Grov vold',           fine = 12000, jail = 30, lawRef = 'Straffeloven § 245' },
        { label = 'Trusler',             fine = 2500,  jail = 5,  lawRef = 'Straffeloven § 266' },
        { label = 'Frihedsberøvelse',    fine = 6000,  jail = 15, lawRef = 'Straffeloven § 261' },
    },
    -- Sådan tilføjer du selv en ny bøde:
    -- { label = 'Ny forseelse', fine = 1000, jail = 0, lawRef = nil },
}
