Config = Config or {}

-- ══════════════════════════════════════════
--  GENERELT
-- ══════════════════════════════════════════
Config.Locale          = 'da'          -- 'da' eller 'en'
Config.Debug           = false         -- true = print debug info i konsollen (aldrig spam, kun relevante events)
Config.Framework       = 'auto'        -- 'auto', 'esx', 'qbcore', 'vrp', 'standalone'

-- ══════════════════════════════════════════
--  EVENT PERIODE
-- ══════════════════════════════════════════
Config.EnableDateCheck = false         -- true = eventet er kun aktivt mellem Start og End dato
Config.StartMonth      = 12
Config.StartDay        = 1
Config.EndMonth        = 12
Config.EndDay          = 31

-- ══════════════════════════════════════════
--  LEVEL SYSTEM
-- ══════════════════════════════════════════
Config.MaxLevel        = 100
-- XP Required = floor(1000 * (level ^ 1.5))

-- ══════════════════════════════════════════
--  JULECOINS
--  Eneste "source of truth" for coins er den faktiske mængde
--  Config.CoinItem i spillerens ox_inventory. Der er IKKE en
--  separat DB-tæller der kan komme ud af sync med inventoryet.
-- ══════════════════════════════════════════
Config.CoinItem        = 'christmas_coin'   -- ox_inventory item navn
Config.MaxCoins        = 5000

-- ══════════════════════════════════════════
--  BELØNNINGER PER LEVEL
-- ══════════════════════════════════════════
-- coins = julecoins, item = item navn, amount = antal
Config.LevelRewards = {
    [1]   = { coins = 10 },
    [2]   = { coins = 15 },
    [3]   = { coins = 20 },
    [4]   = { coins = 25 },
    [5]   = { coins = 30 },
    [6]   = { coins = 35 },
    [7]   = { coins = 40 },
    [8]   = { coins = 45 },
    [9]   = { coins = 50 },
    [10]  = { coins = 75,  item = 'christmas_box', amount = 1 },
    [15]  = { coins = 100 },
    [20]  = { coins = 150, item = 'christmas_box', amount = 1 },
    [25]  = { coins = 200, item = 'christmas_box', amount = 2 },
    [30]  = { coins = 250 },
    [35]  = { coins = 300 },
    [40]  = { coins = 350, item = 'christmas_box', amount = 2 },
    [50]  = { coins = 500, item = 'christmas_box', amount = 5 },
    [60]  = { coins = 600, item = 'christmas_box', amount = 5 },
    [70]  = { coins = 700, item = 'christmas_box', amount = 8 },
    [80]  = { coins = 800, item = 'christmas_box', amount = 10 },
    [90]  = { coins = 900, item = 'christmas_box', amount = 12 },
    [100] = { coins = 1000, item = 'christmas_box', amount = 20 },
}

-- ══════════════════════════════════════════
--  CHRISTMAS BOX
--  chance-værdierne herunder summerer til 100 og fungerer som en
--  ren weighted roll (1-100) - præcis 1 reward vælges altid.
-- ══════════════════════════════════════════
Config.ChristmasBoxItem = 'christmas_box'
Config.ChristmasBoxRewards = {
    { chance = 40, type = 'coins',  amount = 50  },
    { chance = 25, type = 'coins',  amount = 100 },
    { chance = 15, type = 'xp',     amount = 500 },
    { chance = 10, type = 'coins',  amount = 200 },
    { chance = 5,  type = 'item',   item = 'santahat',   amount = 1 },
    { chance = 3,  type = 'item',   item = 'snowglobe',  amount = 1 },
    { chance = 2,  type = 'coins',  amount = 500 },
}

-- ══════════════════════════════════════════
--  PERSONLIGE GAVER (sendt af admin via kommando)
-- ══════════════════════════════════════════
Config.PersonalGiftProp    = 'xm3_prop_xm3_present_01a'
Config.PersonalGiftRewards = {
    xp    = 500,
    coins = 50,
    items = {
        { item = 'christmas_box', amount = 1 },
    }
}
Config.PersonalGiftCommand = 'christmasgift'  -- /christmasgift [id]
-- Hvor lang tid (ms) en personlig gave forbliver aktiv før den udløber
-- automatisk, hvis spilleren ikke når at hente den.
Config.PersonalGiftExpiry  = 3600000 -- 1 time

-- ══════════════════════════════════════════
--  VERDENS-GAVER (findes frit af alle spillere)
--  Bruger samme lokations-pulje som personlige gaver. Hver spiller
--  kan finde/åbne hver lokation præcis én gang (ligesom juletræer).
-- ══════════════════════════════════════════
Config.WorldGiftsEnabled = true
Config.WorldGiftRewards  = { xp = 250, coins = 30 }

-- Mulige spawn-lokationer for personlige OG verdens-gaver
Config.GiftLocations = {
    vec3(298.43,  -584.67,  43.26),
    vec3(-225.01, -958.23,  31.22),
    vec3(350.12,  -1012.56, 29.43),
    vec3(-560.34, -183.45,  37.65),
    vec3(119.87,  -629.45,  43.67),
    vec3(-709.12, 264.34,   92.45),
    vec3(217.56,  -810.23,  30.78),
    vec3(-334.67, 6.89,     39.34),
    vec3(462.34,  -987.45,  26.87),
    vec3(-67.89,  -1756.34, 29.56),
    vec3(138.56,  -2012.78, 21.34),
    vec3(923.45,  -1623.67, 30.45),
    vec3(1386.23, -1534.56, 101.23),
    vec3(-1208.45, -461.23, 36.78),
    vec3(397.34,  302.56,   102.45),
}

-- ══════════════════════════════════════════
--  JULETRÆER
-- ══════════════════════════════════════════
Config.TreeProp  = 'prop_xmas_tree_int'
Config.TreeRewards = { xp = 200, coins = 25 }
Config.Trees = {
    { coords = vec3(309.45,  -584.56,  43.28),  heading = 0.0,   hint = 'Sydvest for MRPD, ved siden af parkeringspladsen' },
    { coords = vec3(-225.34, -957.12,  31.22),  heading = 45.0,  hint = 'Nær Pillbox Hill Medical Center, vest side' },
    { coords = vec3(349.56,  -1011.23, 29.43),  heading = 90.0,  hint = 'La Mesa, langs Olympic Fwy' },
    { coords = vec3(-559.12, -182.34,  37.65),  heading = 180.0, hint = 'Rockford Hills, nær Rockford Dr' },
    { coords = vec3(120.34,  -628.56,  43.67),  heading = 270.0, hint = 'Downtown, nær Innocence Blvd' },
    { coords = vec3(-708.56, 265.78,   92.45),  heading = 0.0,   hint = 'Vinewood Hills, øverst mod nord' },
    { coords = vec3(216.78,  -809.34,  30.78),  heading = 120.0, hint = 'Strawberry, nær Davis Ave' },
    { coords = vec3(-333.45, 7.67,     39.34),  heading = 60.0,  hint = 'West Eclipse Blvd, Morningwood' },
    { coords = vec3(461.23,  -986.56,  26.87),  heading = 200.0, hint = 'LSIA området, øst for lufthavnen' },
    { coords = vec3(-66.78,  -1755.56, 29.56),  heading = 320.0, hint = 'Elysian Island, ved havnen' },
}

-- ══════════════════════════════════════════
--  SNEMÆND
-- ══════════════════════════════════════════
Config.SnowmanProp        = 'prop_prlg_snowpile'
Config.SnowmanRewards     = { xp = 150, coins = 20 }
Config.SnowmanBuildTime   = 5000     -- ms at "bygge" (progress bar, client-side UX)
Config.SnowmanDespawnTime = 1800000  -- ms før en bygget snemand forsvinder og pladsen frigives igen (server-autoritativ)
Config.SnowmanLocations = {
    { coords = vec3(300.12,  -590.34,  43.28), hint = 'Sydvest for MRPD, nær parken' },
    { coords = vec3(-220.45, -960.56,  31.22), hint = 'Nord for Pillbox Hill Hospital' },
    { coords = vec3(345.67,  -1015.34, 29.43), hint = 'La Mesa, ved siden af Olympic Fwy' },
    { coords = vec3(-555.23, -185.67,  37.65), hint = 'Rockford Hills, Rockford Dr' },
    { coords = vec3(115.89,  -632.45,  43.67), hint = 'Innocence Blvd, Downtown' },
    { coords = vec3(-712.34, 268.23,   92.45), hint = 'Vinewood Hills, nordlig park' },
    { coords = vec3(212.56,  -812.67,  30.78), hint = 'Strawberry Ave, syd for hospitalet' },
    { coords = vec3(-330.12, 10.45,    39.34), hint = 'Morningwood, nær West Eclipse Blvd' },
    { coords = vec3(458.78,  -990.23,  26.87), hint = 'Øst for LSIA, nær lufthavnsvej' },
    { coords = vec3(-63.45,  -1758.78, 29.56), hint = 'Elysian Island, havneområdet' },
    { coords = vec3(135.23,  -2015.67, 21.34), hint = 'Terminal, sydlige industriområde' },
    { coords = vec3(920.12,  -1626.89, 30.45), hint = 'East Vinewood, nær Olympic Fwy' },
}

-- ══════════════════════════════════════════
--  OPGAVER
-- ══════════════════════════════════════════
Config.DailyTaskCount   = 3    -- antal daglige opgaver der tildeles
Config.WeeklyTaskCount  = 2    -- antal ugentlige opgaver der tildeles

Config.DailyTasks = {
    { id = 'd_drive_5',    type = 'drive',    target = 5000,  label = 'Kør 5 km',         xp = 200,  coins = 25  },
    { id = 'd_drive_25',   type = 'drive',    target = 25000, label = 'Kør 25 km',        xp = 500,  coins = 60  },
    { id = 'd_run_5',      type = 'run',      target = 5000,  label = 'Løb 5 km',         xp = 300,  coins = 35  },
    { id = 'd_run_10',     type = 'run',      target = 10000, label = 'Løb 10 km',        xp = 600,  coins = 70  },
    { id = 'd_trees_3',    type = 'trees',    target = 3,     label = 'Pynt 3 juletræer', xp = 400,  coins = 50  },
    { id = 'd_snowmen_5',  type = 'snowmen',  target = 5,     label = 'Byg 5 snemænd',    xp = 350,  coins = 45  },
    { id = 'd_gifts_3',    type = 'gifts',    target = 3,     label = 'Find 3 gaver',     xp = 300,  coins = 40  },
}

Config.WeeklyTasks = {
    { id = 'w_drive_50',   type = 'drive',    target = 50000, label = 'Kør 50 km',         xp = 1500, coins = 200 },
    { id = 'w_run_25',     type = 'run',      target = 25000, label = 'Løb 25 km',         xp = 2000, coins = 250 },
    { id = 'w_trees_10',   type = 'trees',    target = 10,    label = 'Pynt 10 juletræer', xp = 1800, coins = 220 },
    { id = 'w_snowmen_10', type = 'snowmen',  target = 10,    label = 'Byg 10 snemænd',    xp = 1600, coins = 200 },
    { id = 'w_gifts_5',    type = 'gifts',    target = 5,     label = 'Find 5 gaver',      xp = 1400, coins = 180 },
}

-- ══════════════════════════════════════════
--  JULE SHOP
-- ══════════════════════════════════════════
Config.ShopItems = {
    -- ── Mystery Boxes ──
    { id = 'shop_cbox_small',     label = 'Christmas Box',      type = 'item', item = 'christmas_box',   price = 300,   limit = 10,  icon = '🎁' },
    { id = 'shop_cbox_large',     label = 'Stor Christmas Box', type = 'item', item = 'christmas_box',   price = 700,   limit = 5,   icon = '🎄' },
    -- ── Trækasser / ressourcer ──
    { id = 'shop_woodbox',        label = 'Trækasse',           type = 'item', item = 'wood_box',        price = 500,   limit = 5,   icon = '📦' },
    { id = 'shop_goldbar',        label = 'Guldbarre',          type = 'item', item = 'goldbar',         price = 1500,  limit = 3,   icon = '🪙' },
    { id = 'shop_glass',          label = 'Glas',               type = 'item', item = 'glass',           price = 200,   limit = 10,  icon = '🔮' },
    -- ── Våben ──
    { id = 'shop_weapon_candy',   label = 'Weapon Candycane',   type = 'item', item = 'weapon_candycane',price = 3000,  limit = 1,   icon = '🍬' },
    -- ── Cosmetics ──
    { id = 'shop_santahat',       label = 'Julemandshue',       type = 'item', item = 'santahat',        price = 250,   limit = 1,   icon = '🎅' },
    { id = 'shop_reindeer',       label = 'Rensdyr Maske',      type = 'item', item = 'reindeer_mask',   price = 500,   limit = 1,   icon = '🦌' },
    { id = 'shop_elf_suit',       label = 'Nissedragt',         type = 'item', item = 'elf_suit',        price = 750,   limit = 1,   icon = '🧝' },
    { id = 'shop_xmas_socks',     label = 'Julestrømper',      type = 'item', item = 'xmas_socks',      price = 100,   limit = 2,   icon = '🧦' },
}

-- ══════════════════════════════════════════
--  EMOTES / ANIMATIONER
-- ══════════════════════════════════════════
Config.Animations = {
    openGift  = { dict = 'mp_player_int_celebrationreact',       anim = 'mp_player_int_celebrationreact_a', duration = 3000 },
    decorTree = { dict = 'anim@mp_player_intcelebrationmale@thumbs_up', anim = 'thumbs_up',                duration = 2500 },
    buildSnow = { dict = 'amb@world_human_gardener_plant@male@base',    anim = 'base',                     duration = 5000 },
}

-- ══════════════════════════════════════════
--  LEADERBOARD
-- ══════════════════════════════════════════
Config.LeaderboardSize    = 10
Config.LeaderboardRefresh = 60000  -- ms mellem opdateringer

-- ══════════════════════════════════════════
--  ADMIN
-- ══════════════════════════════════════════
Config.AdminGroups = { 'admin', 'superadmin', 'god', 'mod' }
Config.AdminName   = 'Admin'

-- ══════════════════════════════════════════
--  SECURITY / ANTI-EXPLOIT
--  Server-side sanity-grænser. Clienten kan ALDRIG omgå disse -
--  serveren clamper/afviser altid værdier der overskrider dem.
-- ══════════════════════════════════════════
Config.Distance = {
    -- Maks meter der accepteres PR. trackDistance-rapport (klienten
    -- rapporterer hvert Config.Distance.ReportInterval ms). Alt over
    -- dette klippes ned til grænsen i stedet for at blive afvist helt,
    -- så en enkelt outlier-rapport (fx pga. lag) ikke straffer spilleren
    -- unødigt, men et forsøg på at rapportere 500 km er meningsløst.
    MaxDrivenPerReport = 2000,   -- meter (svarer til ~720 km/t i 10 sek)
    MaxRunPerReport    = 300,    -- meter (svarer til ~108 km/t i 10 sek)
    ReportInterval     = 10000,  -- ms — skal matche client.lua's SEND_INTERVAL
}

-- Radius (meter) spilleren skal være indenfor en location for at en
-- server-valideret handling (pynt træ, byg snemand, find gave) accepteres.
-- Sat lidt højere end klientens egen ox_target-distance for at tolerere
-- netværks-lag uden at åbne for fjern-exploits.
Config.InteractionRadius = 5.0

-- Minimum tid (ms) mellem to trigger af samme event fra samme spiller.
-- Beskytter mod spam/dobbeltklik uden at genere normal spilleradfærd.
Config.RateLimits = {
    playerJoin        = 2000,
    openUI            = 800,
    shopBuy           = 800,
    openBox           = 1000,
    decorateTree      = 1500,
    buildSnowman      = 1500,
    giftFound         = 1000,
    worldGift         = 1000,
    claimLevelReward  = 500,
    -- Sat til lige under Config.Distance.ReportInterval: en legitim
    -- client kan pr. design ALDRIG sende hurtigere end ReportInterval,
    -- så denne grænse koster spillere intet, men lukker for at et
    -- direkte event-kald kunne spamme trackDistance hurtigere end
    -- klienten selv gør for at omgå MaxDrivenPerReport-loftet over tid.
    trackDistance     = 9500,
    getLeaderboard    = 2000,
    getProfileImage   = 5000,
}

-- ══════════════════════════════════════════
--  PROFILBILLEDE (Steam / Discord avatar)
--  steamApiKey og discordBotToken bruges KUN server-side
--  (server/avatar.lua) og sendes ALDRIG til client/NUI.
-- ══════════════════════════════════════════
Config.ProfileImage = {
    -- 'auto' = prøv Discord først, derefter Steam, derefter fallback.
    -- 'discord' / 'steam' = brug kun denne udbyder.
    -- 'none'  = deaktiver profilbilleder helt (viser altid fallback).
    provider = 'auto',

    -- Hvor længe (sekunder) et hentet avatar-link caches server-side,
    -- før der forsøges hentet et nyt ved næste request.
    cacheTime = 3600,

    -- Sæt jeres egne API-nøgler her. Efterlades de tomme, springes den
    -- pågældende udbyder automatisk over (falder videre til fallback)
    -- uden at det påvirker resten af UI'en.
    steamApiKey     = '',
    discordBotToken = '',
}

-- ══════════════════════════════════════════
--  UI
-- ══════════════════════════════════════════
Config.UI = {
    MinWidth  = 1000,
    MinHeight = 640,
    MaxWidth  = 1280,
    MaxHeight = 800,

    -- Hvor lang tid (ms) loading screenet minimum vises når UI'et åbnes.
    -- Sættes til 0 for at deaktivere loading screenet helt.
    LoadingDuration = 900,

    -- 'snow' | 'santa' | 'trees' | 'reindeer'
    DefaultTheme = 'snow',

    EnableAnimations = true,
    EnableSnow       = true,
    EnableSounds     = true,
}
