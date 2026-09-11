-- ============================================================
--  MPvp-idmenu | config.lua
--  Rent ID-peek system til MPvp. Ingen menu, ingen NUI.
-- ============================================================

Config = {}

-- ─── TAST ────────────────────────────────────────────────────
-- Bruges via RegisterKeyMapping — spilleren kan selv rebinde den i
-- FiveM's egne indstillinger (F8 > Settings > Key Bindings > FiveM).
Config.Key = 'PAGEDOWN'

-- ─── SYNLIGHED ───────────────────────────────────────────────
Config.Distance = 100.0            -- maks. afstand (i meter) et ID vises på
Config.RequireLineOfSight = true   -- true = kun vis ID hvis spilleren rent faktisk kan ses
Config.ShowDeadPlayers = true      -- false = døde spillere får ikke vist ID

-- ─── OFFSET ──────────────────────────────────────────────────
Config.PlayerIdOffset = 1.0        -- Z-offset over hovedet på en spiller til fods
Config.VehicleIdOffset = 1.5       -- Z-offset når spilleren sidder i et køretøj

-- ─── OPDATERINGS-INTERVAL ────────────────────────────────────
-- Hvor tit spiller-cachen (aktive spillere/serverID/ped) genopbygges
-- MENS ID-peek er aktivt. Selve tegningen sker stadig hvert frame (det
-- er et krav fra GTA's text/rect-natives), men den tunge del —
-- GetActivePlayers()/GetPlayerServerId() — laves kun med dette interval.
Config.CacheInterval = 500 -- ms

-- ─── TEKST ───────────────────────────────────────────────────
Config.Text = {
    font    = 4,
    scale   = 0.30,
    color   = { 225, 225, 227, 255 }, -- diskret off-white, ikke ren neon-hvid
    outline = true,                   -- SetTextOutline() for læsbarhed uden en NUI-skygge
}

-- ─── BAGGRUND (badge-look, matcher MPvp's #141517) ──────────
Config.Background = {
    enabled  = true,
    color    = { 20, 21, 23, 210 }, -- #141517
    paddingX = 0.0040,
    paddingY = 0.0035,
}

Config.Border = {
    enabled   = true,
    color     = { 255, 255, 255, 30 }, -- meget diskret, næsten usynlig kant
    thickness = 0.0006,
}

-- ─── VALGFRI FARVE BASERET PÅ AFSTAND ────────────────────────
-- Slået fra som standard for at holde renderingen så simpel/billig som
-- muligt. Slå til hvis du vil have et visuelt distance-hint.
Config.DistanceColors = {
    enabled = false,
    close   = { distance = 15.0,  color = { 255, 255, 255, 255 } },
    medium  = { distance = 50.0,  color = { 200, 200, 200, 255 } },
    far     = { distance = 100.0, color = { 140, 140, 140, 255 } },
}
