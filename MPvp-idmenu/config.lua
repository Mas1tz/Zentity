-- ============================================================
--  MPvp-idmenu | config.lua
--  Rent ID + navn-peek system til MPvp. Ingen menu, ingen NUI.
-- ============================================================

Config = Config or {}

Config.IDPeek = {
    enabled = true,

    -- Bruges via RegisterKeyMapping (ikke et konstant polling-loop) —
    -- 'PAGEDOWN' svarer til den klassiske rå control-id 207, men giver
    -- reel 0.00ms idle for selve tast-aktiveringen, OG lader spilleren
    -- selv rebinde tasten i FiveM's egne indstillinger (F8 > Settings >
    -- Key Bindings > FiveM).
    key = 'PAGEDOWN',

    distance = 30.0,  -- maks. afstand (meter) et ID/navn vises på
    height   = 1.0,   -- Z-offset over hovedet på en spiller til fods
    vehicleHeight = 1.5, -- Z-offset når spilleren sidder i et køretøj

    showId   = true,
    showName = true,

    lineOfSight = false, -- true = kræver at spilleren rent faktisk kan ses
    showDeadPlayers = true,
    showPlayersInVehicles = true,

    -- Hvor tit spiller-cachen (server-ID/navn/ped) genopbygges MENS
    -- ID-peek er aktivt. Selve tegningen sker stadig hvert frame (et
    -- krav fra GTA's text-natives), men de tunge kald
    -- (GetActivePlayers/GetPlayerServerId/GetPlayerName) laves kun med
    -- dette interval, ikke hvert frame.
    cacheInterval = 500, -- ms

    text = {
        font = 4,

        idScale   = 0.40,
        nameScale = 0.30,

        -- Lodret placering ift. World3dToScreen2d-ankerpunktet (Config.IDPeek.height).
        -- Positiv = længere nede på skærmen.
        idOffset   = 0.0,
        nameOffset = 0.025,

        -- ID skal være mere fremtrædende end navnet — lidt lysere/skarpere.
        idColor   = { 235, 235, 238, 255 },
        nameColor = { 180, 180, 184, 235 },

        outline = true,
    },

    background = {
        enabled  = true,
        color    = { 20, 21, 23, 210 }, -- #141517
        paddingX = 0.0040,
        paddingY = 0.0035,
    },

    border = {
        enabled   = true,
        color     = { 255, 255, 255, 30 }, -- meget diskret, næsten usynlig kant
        thickness = 0.0006,
    },

    -- Valgfri farve baseret på afstand — slået fra som standard for at
    -- holde renderingen så simpel/billig som muligt.
    distanceColors = {
        enabled = false,
        close   = { distance = 10.0, idColor = { 255, 255, 255, 255 }, nameColor = { 210, 210, 210, 255 } },
        medium  = { distance = 20.0, idColor = { 220, 220, 220, 255 }, nameColor = { 180, 180, 180, 255 } },
        far     = { distance = 30.0, idColor = { 190, 190, 190, 255 }, nameColor = { 150, 150, 150, 255 } },
    },
}
