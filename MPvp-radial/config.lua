-- ============================================================
--  MPvp-radial | config.lua
--  4 funktioner, ét radial-hjul: Noclip, Revive, Lobby, Report.
-- ============================================================

Config = {}

Config.Debug = false

-- ─── NOCLIP ──────────────────────────────────────────────────
Config.Noclip = {
    -- Multiplikatorer, ikke rå m/s — se client/main.lua's NOCLIP_BASE_SPEED
    -- for den faktiske skalering (framerate-uafhængig via GetFrameTime()).
    speed     = 1.0,  -- normal fart
    fastSpeed = 5.0,  -- VENSTRE SHIFT
    slowSpeed = 0.25, -- HØJRE MUSEKNAP (præcisionsbevægelse)
}

-- ─── REVIVE ──────────────────────────────────────────────────
-- Bevarer den eksisterende esx_ambulancejob-integration uændret — kun
-- selve kaldet er nu beskyttet af et dødstjek + en cooldown, så det
-- ikke kan bruges som et gratis, ubegrænset selv-heal midt i en fight.
Config.Revive = {
    enabled  = true,
    event    = 'esx_ambulancejob:revive', -- den eksisterende ESX-integration
    cooldown = 5000, -- ms
}

-- ─── LOBBY ───────────────────────────────────────────────────
-- Der blev IKKE fundet nogen eksisterende lobby-integration i den
-- oprindelige resource. Sæt exportResource/exportName hvis I allerede
-- har et separat lobby-system — så kaldes det i stedet for at
-- teleportere direkte. Ellers bruges `coords` som standard.
Config.Lobby = {
    enabled  = true,
    coords   = vec4(0.0, 0.0, 72.0, 0.0), -- SKAL sættes til jeres rigtige lobby-punkt
    exportResource = nil,
    exportName     = nil,
}

-- ─── REPORT ──────────────────────────────────────────────────
Config.Report = {
    enabled         = true,
    cooldown        = 10000, -- ms, server-side, pr. spiller
    maxReasonLength = 250,
    minReasonLength = 3,

    -- Kun server-side. Tomt = ingen webhook sendt.
    webhook  = '',
    username = 'MPvp Reports',

    -- Valgfrit: navnet på en ACE-permission (fx 'mpvp.staff') der skal
    -- have en in-game notifikation når en report kommer ind. Sæt til
    -- nil for at springe det over og kun bruge webhook/konsol.
    notifyAce = nil,
}

-- ─── UI (bruges KUN til det lille native noclip-statusmærke —
--     radial-hjulet/notify/inputDialog styres af ox_lib's eget,
--     server-fælles tema og kan ikke re-farves herfra) ────────────
Config.UI = {
    background = { 20, 21, 23, 210 },  -- #141517
    surface    = { 46, 46, 46, 235 },  -- #2e2e2e
    text       = { 242, 242, 242, 255 },
    textMuted  = { 154, 154, 154, 255 },
}
