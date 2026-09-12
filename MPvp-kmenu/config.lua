-- ============================================================
--  MPvp-kmenu | config.lua
--  MPvp Weapon Hub — ren NUI, server-autoritativ udlevering.
-- ============================================================

Config = {}

Config.Debug = false

-- ─── ÅBNING ──────────────────────────────────────────────────
-- RegisterKeyMapping — spilleren kan selv rebinde den i FiveM's
-- keybind-indstillinger.
Config.Key = 'K'

-- ─── OX_INVENTORY BILLEDER ───────────────────────────────────
-- Genbruger ox_inventory's egne billeder — ingen dubletter, ingen
-- base64. NUI'en bygger selv den fulde sti som imagePath .. image.
Config.InventoryImagePath = 'nui://ox_inventory/web/images/'

-- ─── ANTI-SPAM ───────────────────────────────────────────────
Config.GiveCooldown = 500 -- ms mellem hver udlevering, PR. SPILLER, server-side

-- ─── ANTAL (items — våben er ALTID 1, håndhævet server-side) ──
Config.MaxItemAmount = 20 -- standard-loft, kan overskrives pr. item med `maxAmount`

-- ─── DISCORD-LOGGING (kun server-side, ALDRIG i NUI/klient) ──
Config.Logging = {
    enabled  = false,
    webhook  = '',
    username = 'MPvp Security',
}

-- ─── UI-FARVER (matcher NUI'ens style.css 1:1) ────────────────
Config.UI = {
    background    = '#141517',
    surface       = '#2e2e2e',
    surfaceHover  = '#363636',
    text          = '#f2f2f2',
    textSecondary = '#9a9a9a',
    textMuted     = '#666666',
    border        = 'rgba(255,255,255,0.05)',
}

-- ============================================================
--  KATEGORIER — ren visnings-metadata (rækkefølge, dansk label,
--  ikon-nøgle brugt i web/app.js). At tilføje en ny kategori
--  (Melee, Snipers, Armor, osv.) kræver KUN én linje her + én ny
--  tabel i Config.Weapons herunder.
-- ============================================================
Config.Categories = {
    { key = 'Pistol',     label = 'Pistoler',    icon = 'pistol'     },
    { key = 'SMG',        label = 'SMG\'er',      icon = 'smg'        },
    { key = 'Rifle',      label = 'Rifler',      icon = 'rifle'      },
    { key = 'Shotgun',    label = 'Shotguns',    icon = 'shotgun'    },
    { key = 'Attachment', label = 'Attachments', icon = 'attachment' },
    { key = 'Tilbehoer',  label = 'Tilbehør',    icon = 'gear'       },
}

-- ============================================================
--  VÅBEN/ITEMS — DENNE tabel er den ENESTE kilde til sandhed.
--  server.lua bygger sin whitelist herfra ved opstart — et
--  våben/item der ikke står her kan ALDRIG gives, uanset hvad en
--  klient sender.
--
--  Felter:
--    label     — dansk visningsnavn
--    weapon    — ox_inventory/weapon-navn (våben, altid antal 1)
--    item      — ox_inventory item-navn (kan gives i antal)
--    maxAmount — valgfri override af Config.MaxItemAmount (kun items)
--    image     — udledes automatisk som `<weapon|item>.png`
-- ============================================================
Config.Weapons = {
    Pistol = {
        { label = 'Pistol',           weapon = 'weapon_pistol' },
        { label = 'Pistol MK2',       weapon = 'weapon_pistol_mk2' },
        { label = 'Combat Pistol',    weapon = 'weapon_combatpistol' },
        { label = 'APPistol',         weapon = 'weapon_appistol' },
        { label = 'Pistol50',         weapon = 'weapon_pistol50' },
        { label = 'SNS Pistol',       weapon = 'weapon_snspistol' },
        { label = 'SNS Pistol MK2',   weapon = 'weapon_snspistol_mk2' },
        { label = 'Heavy Pistol',     weapon = 'weapon_heavypistol' },
        { label = 'Vintage Pistol',   weapon = 'weapon_vintagepistol' },
        { label = 'Marksman Pistol',  weapon = 'weapon_marksmanpistol' },
        { label = 'Revolver',         weapon = 'weapon_revolver' },
        { label = 'Revolver MK2',     weapon = 'weapon_revolver_mk2' },
        { label = 'Doubleaction',     weapon = 'weapon_doubleaction' },
        { label = 'Ceramic Pistol',   weapon = 'weapon_ceramicpistol' },
        { label = 'Navy Revolver',    weapon = 'weapon_navyrevolver' },
        { label = 'Gadget Pistol',    weapon = 'weapon_gadgetpistol' },
        { label = 'Pistol XM3',       weapon = 'weapon_pistolxm3' },
    },
    SMG = {
        { label = 'Micro SMG',      weapon = 'weapon_microsmg' },
        { label = 'SMG',            weapon = 'weapon_smg' },
        { label = 'SMG MK2',        weapon = 'weapon_smg_mk2' },
        { label = 'Assault SMG',    weapon = 'weapon_assaultsmg' },
        { label = 'Combat PDW',     weapon = 'weapon_combatpdw' },
        { label = 'Machine Pistol', weapon = 'weapon_machinepistol' },
        { label = 'Mini SMG',       weapon = 'weapon_minismg' },
        { label = 'Tec Pistol',     weapon = 'weapon_tecpistol' },
    },
    Rifle = {
        { label = 'Assault Rifle',      weapon = 'weapon_assaultrifle' },
        { label = 'Assault Rifle MK2',  weapon = 'weapon_assaultrifle_mk2' },
        { label = 'Carbine Rifle',      weapon = 'weapon_carbinerifle' },
        { label = 'Carbine Rifle MK2',  weapon = 'weapon_carbinerifle_mk2' },
        { label = 'Advanced Rifle',     weapon = 'weapon_advancedrifle' },
        { label = 'Special Rifle',      weapon = 'weapon_specialcarbine' },
        { label = 'Special Rifle MK2',  weapon = 'weapon_specialcarbine_mk2' },
        { label = 'Bullpup Rifle',      weapon = 'weapon_bullpuprifle' },
        { label = 'Bullpup Rifle MK2',  weapon = 'weapon_bullpuprifle_mk2' },
        { label = 'Compact Rifle',      weapon = 'weapon_compactrifle' },
        { label = 'Military Rifle',     weapon = 'weapon_militaryrifle' },
        { label = 'Heavy Rifle',        weapon = 'weapon_heavyrifle' },
        { label = 'Tactical Rifle',     weapon = 'weapon_tacticalrifle' },
        { label = 'Gusenberg',          weapon = 'weapon_gusenberg' },
    },
    Shotgun = {
        { label = 'Pump Shotgun',       weapon = 'weapon_pumpshotgun' },
        { label = 'Pump Shotgun MK2',   weapon = 'weapon_pumpshotgun_mk2' },
        { label = 'Sawed-Off Shotgun',  weapon = 'weapon_sawnoffshotgun' },
        { label = 'Assault Shotgun',    weapon = 'weapon_assaultshotgun' },
        { label = 'Bullpup Shotgun',    weapon = 'weapon_bullpupshotgun' },
        { label = 'Heavy Shotgun',      weapon = 'weapon_heavyshotgun' },
        { label = 'DB Shotgun',         weapon = 'weapon_dbshotgun' },
        { label = 'Auto Shotgun',       weapon = 'weapon_autoshotgun' },
        { label = 'Combat Shotgun',     weapon = 'weapon_combatshotgun' },
    },
    Attachment = {
        { label = 'Scope',          item = 'scope_attachment' },
        { label = 'Flashlight',     item = 'flashlight_attachment' },
        { label = 'Extended Clip',  item = 'clip_attachment' },
        { label = 'Grip',           item = 'grip_attachment' },
        { label = 'Suppressor',     item = 'suppressor_attachment' },
    },
    Tilbehoer = {
        { label = 'Skudsikker vest', item = 'armour',  maxAmount = 5 },
        { label = 'Skud',            item = 'ammo',    maxAmount = 20 },
        { label = 'Bandage',         item = 'bandage', maxAmount = 20 },
        { label = 'Radio',           item = 'radio',   maxAmount = 1 },
    },
}
