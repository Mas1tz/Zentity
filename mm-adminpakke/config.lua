-- ============================================================
--  mm-adminpakke V2 | config.lua
--  ESX Legacy · ox_lib · ox_inventory
-- ============================================================

Config = Config or {}

Config.Debug = false

-- ------------------------------------------------------------------
--  ÅBNING
-- ------------------------------------------------------------------
Config.OpenCommand = 'adminpack'
Config.OpenKey = 'F6' -- sæt til nil for at deaktivere keybind (kommandoen virker stadig)

-- ------------------------------------------------------------------
--  RETTIGHEDER
-- ------------------------------------------------------------------
Config.UseAcePermission = false -- true = brug kun ace-permission herunder
Config.AcePermission = 'mmadminpakke.use'

Config.AllowedGroups = {
    'admin',
    'superadmin',
    'god',
    'moderator',
}

-- ------------------------------------------------------------------
--  SIKKERHED / RATE LIMIT
-- ------------------------------------------------------------------
Config.RateLimit = {
    Enabled = true,
    MaxRequests = 5,     -- max requests
    WindowSeconds = 10,  -- pr. dette antal sekunder
}

-- Enkelt-item grænse. Dette er den grænse der reelt håndhæves - både
-- klient (UI kan ikke engang skrive højere) OG server (autoritativ,
-- klienten kan aldrig omgå denne).
Config.MaxItemAmount = 5000

-- Kurven kan indeholde flere varetyper på én gang - dette er et samlet
-- loft for HELE kurven, adskilt fra enkelt-item grænsen ovenfor, så det
-- er muligt at give 5000 af ét item OG andre items i samme afsendelse.
Config.MaxBasketItems = 50         -- max unikke varetyper i kurven
Config.MaxBasketTotalAmount = 100000 -- rent DoS-sikkerhedsnet, ikke en daglig grænse -
                                      -- sat højt nok til at 5000 af flere forskellige
                                      -- items samtidig ALDRIG kolliderer med denne

-- Items der aldrig kan gives via panelet, uanset hvem der forsøger.
Config.BlacklistedItems = {
    'weapon_rpg',
    'weapon_minigun',
    'weapon_railgun',
    'ammo_rocket',
}

-- ------------------------------------------------------------------
--  LOGGING
-- ------------------------------------------------------------------
Config.Logging = {
    Console = true,
    Discord = true,
}

Config.DiscordWebhook = 'YOUR_WEBHOOK_URL_HERE'

Config.DiscordEmbed = {
    Username = 'mm-adminpakke',
    AvatarUrl = '',
    Color = 5010677, -- #4c6ef5 som decimal
}

-- ------------------------------------------------------------------
--  UI / TEMA
--  Farverne herfra sendes til NUI ved åbning og sættes som CSS
--  custom properties - konfigurerer man dem her, ændres den faktiske
--  visning, det er ikke bare dekorativt.
-- ------------------------------------------------------------------
Config.ItemsPerPage = 40

Config.Theme = {
    Background = '#2e2e2e',
    Accent     = '#4c6ef5',
}

-- ------------------------------------------------------------------
--  ITEM IMAGES
-- ------------------------------------------------------------------
-- Basissti ox_inventory server sine billeder fra. 'nui://<resource>/<sti>'
-- er den korrekte protokol i FiveM's NUI-browser. Skift kun dette hvis
-- din ox_inventory-installation rent faktisk server billeder fra en
-- anden mappe end standarden.
Config.ImageBasePath = 'nui://ox_inventory/web/images'

-- Manuel override for enkelte items hvor det faktiske filnavn afviger
-- fra item-navnet (fx name='goldchain10k' men filen hedder faktisk
-- '10kgoldchain.png'). Højeste prioritet i billed-opløsningen.
Config.ImageOverrides = {
    -- ['itemname'] = 'rigtigt_filnavn.png',
}

-- ------------------------------------------------------------------
--  KATEGORIER
--  Rækkefølgen betyder noget: første match vinder. Et item der ikke
--  matcher noget herunder, og som ikke er et våben, havner automatisk
--  i "Ukategoriseret" - det forsvinder ALDRIG fra UI'et.
--
--  match = liste af understrenge der tjekkes mod item-navnet (case
--  insensitive, "includes"-match, ikke kun prefix).
-- ------------------------------------------------------------------
Config.Categories = {
    { id = 'ammunition', label = 'Ammunition', icon = '🎯', match = { 'ammo' } },
    { id = 'mad',         label = 'Mad',         icon = '🍔', match = { 'burger', 'bread', 'food', 'sandwich', 'pizza', 'apple', 'meal', 'snack', 'chip', 'candy', 'donut' } },
    { id = 'drikke',      label = 'Drikke',      icon = '🥤', match = { 'water', 'cola', 'juice', 'beer', 'drink', 'soda', 'wine', 'whiskey', 'vodka', 'coffee', 'tea' } },
    { id = 'drugs',       label = 'Drugs',       icon = '💊', match = { 'weed', 'coke', 'meth', 'lsd', 'heroin', 'drug', 'joint', 'pill_ecstasy' } },
    { id = 'materialer',  label = 'Materialer',  icon = '🧱', match = { 'metal', 'plastic', 'steel', 'wood', 'cloth', 'material', 'iron', 'copper', 'glass', 'rubber', 'fabric', 'wool' } },
    { id = 'tools',       label = 'Tools',       icon = '🔧', match = { 'tool', 'wrench', 'screwdriver', 'hammer', 'drill', 'repairkit', 'lockpick', 'toolkit' } },
    { id = 'medicin',     label = 'Medicin',     icon = '💉', match = { 'bandage', 'medkit', 'morphine', 'painkiller', 'firstaid', 'pill', 'ifak', 'medicine', 'suture' } },
}

Config.UncategorizedLabel = 'Ukategoriseret'
Config.UncategorizedIcon  = '❔'
Config.WeaponsLabel = 'Våben'
Config.WeaponsIcon  = '🔫'

-- ------------------------------------------------------------------
--  MISSING IMAGES MANAGER
-- ------------------------------------------------------------------
Config.MissingImageManager = {
    Enabled = true,
}

-- ------------------------------------------------------------------
--  STEAM INTEGRATION
--  API-nøglen bruges UDELUKKENDE server-side (server/steam.lua). Den
--  sendes ALDRIG til NUI/klienten - kun det færdige navn/avatar-url.
-- ------------------------------------------------------------------
Config.Steam = {
    Enabled = true,
    ApiKey = '9BDE553C96A7C057E83D1C04E5E23798',
    CacheSeconds = 3600, -- hvor længe et Steam-opslag genbruges pr. spiller
}

-- ------------------------------------------------------------------
--  TABLET PROP + ANIMATION
-- ------------------------------------------------------------------
Config.Tablet = {
    Enabled = true,
    Dict  = 'amb@world_human_seat_wall_tablet@female@base',
    Anim  = 'base',
    Prop  = `prop_cs_tablet`,
    Bone  = 28422, -- højre hånd
    Offset = { x = 0.0, y = 0.0, z = 0.03 },
    Rotation = { x = 0.0, y = 0.0, z = 0.0 },
    Flag = 50,
}

-- ------------------------------------------------------------------
--  NOTIFIKATIONER (ox_lib)
-- ------------------------------------------------------------------
Config.Notify = function(src, msg, notifyType)
    TriggerClientEvent('ox_lib:notify', src, {
        type = notifyType or 'inform',
        title = 'mm-adminpakke',
        description = msg,
        duration = 4000,
    })
end
