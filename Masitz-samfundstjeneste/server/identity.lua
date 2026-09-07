--[[
    Identity-modulet henter Steam-navn/avatar via Steam Web API. Dette
    sker UDELUKKENDE server-side — nøglen forlader aldrig denne fil.
    Discord-ID hentes allerede fra GetPlayerIdentifiers i players.lua/
    permissions.lua; Discord-BRUGERNAVN/avatar kræver en bot-integration
    med et Discord-token, hvilket er uden for denne resources scope, men
    discord_name/discord_avatar-felterne i databasen står klar til at
    blive udfyldt af jeres eget Discord-system (se README).

    OPSÆTNING: tilføj til server.cfg, FØR "ensure Masitz-samfundstjeneste":
        set steam_webApiKey "din-nøgle-her"
]]

Identity = {}

local function GetSteamApiKey()
    local key = GetConvar('steam_webApiKey', '')
    if key == '' then return nil end
    return key
end

-- Konverterer FiveM's steam:HEX-identifier til det decimale SteamID64
-- som Steam Web API forventer.
local function SteamHexToId64(steamIdentifier)
    if not steamIdentifier then return nil end
    local hex = steamIdentifier:gsub('steam:', '')
    return tostring(tonumber(hex, 16))
end

-- ------------------------------------------------------------
-- Opdaterer en spillers Steam-felter asynkront. Kaldes ved login, og
-- respekterer Config.Identity.steamCacheMinutes så vi ikke spammer
-- Steam's API hver gang en spiller connecter.
-- ------------------------------------------------------------
function Identity.RefreshSteam(identifier, source)
    if not Config.Samfundstjeneste.Identity.steamEnabled then return end

    local data = Players[identifier]
    if not data then return end

    local apiKey = GetSteamApiKey()
    if not apiKey then return end -- ikke konfigureret — spring stille over

    if data.steam_avatar_updated_at then
        local parsed = os.time({
            year = tonumber(data.steam_avatar_updated_at:sub(1, 4)),
            month = tonumber(data.steam_avatar_updated_at:sub(6, 7)),
            day = tonumber(data.steam_avatar_updated_at:sub(9, 10)),
            hour = tonumber(data.steam_avatar_updated_at:sub(12, 13)),
            min = tonumber(data.steam_avatar_updated_at:sub(15, 16)),
            sec = tonumber(data.steam_avatar_updated_at:sub(18, 19)),
        })
        local cacheSeconds = Config.Samfundstjeneste.Identity.steamCacheMinutes * 60
        if parsed and (os.time() - parsed) < cacheSeconds then
            return -- stadig frisk nok, spring API-kaldet over
        end
    end

    local steamIdentifierRaw = GetPlayerIdentifierByType(source, 'steam')
    local steamId64 = SteamHexToId64(steamIdentifierRaw)
    if not steamId64 then return end

    local url = ('https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s')
        :format(apiKey, steamId64)

    PerformHttpRequest(url, function(statusCode, responseBody)
        if statusCode ~= 200 or not responseBody then return end

        local decoded = Utils.SafeJsonDecode(responseBody)
        local player = decoded
            and decoded.response
            and decoded.response.players
            and decoded.response.players[1]

        if not player then return end

        local cache = Players[identifier]
        if not cache then return end -- spilleren nåede at disconnecte

        cache.steam_id = steamId64
        cache.steam_name = player.personaname
        cache.steam_avatar = player.avatarfull
        cache.steam_avatar_updated_at = os.date('%Y-%m-%d %H:%M:%S')

        SavePlayer(identifier)
        PushPlayerUpdate(identifier)
    end, 'GET', '', {})
end

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local identifier = GetIdentifier(playerId)
    if not identifier then return end

    -- Vent én tick så GetOrCreatePlayerByIdentifier (players.lua, samme
    -- event) har nået at oprette cachen først.
    CreateThread(function()
        Wait(500)
        Identity.RefreshSteam(identifier, playerId)
    end)
end)
