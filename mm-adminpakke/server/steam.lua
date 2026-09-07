-- ============================================================
--  mm-adminpakke V2 | server/steam.lua
--
--  Henter Steam-navn/avatar til spillerkort. API-nøglen bruges
--  UDELUKKENDE her, server-side - den sendes aldrig til NUI/klienten,
--  kun det færdige resultat (navn + avatar-url).
-- ============================================================

local Steam = {}

local function DebugPrint(fmt, ...)
    if not Config.Debug then return end
    print(('[mm-adminpakke] ' .. fmt):format(...))
end

local cache = {} -- [steamId64] = { data = {...}, expiresAt = number }

--- Finder spillerens SteamID64 (som streng) ud fra deres identifiers.
--- Lua 5.4 har native 64-bit heltal, så hex->decimal er præcis.
local function GetSteamId64(src)
    local identifiers = GetPlayerIdentifiers(src)
    for _, id in ipairs(identifiers) do
        local hex = id:match('^steam:(%x+)$')
        if hex then
            local ok, num = pcall(tonumber, hex, 16)
            if ok and num then
                return tostring(num)
            end
        end
    end
    return nil
end

--- Synkront (via promise/await) Steam-opslag, cachet pr. SteamID64.
--- Kaldes fra en callback-kontekst (coroutine), så Await her blokerer
--- IKKE andre spilleres requests.
function Steam.GetProfile(src)
    if not Config.Steam.Enabled then return nil end
    if not Config.Steam.ApiKey or Config.Steam.ApiKey == '' then return nil end

    local steamId64 = GetSteamId64(src)
    if not steamId64 then
        DebugPrint('Spiller %s har ikke et steam-identifier - springer Steam-opslag over.', src)
        return nil
    end

    local now = os.time()
    local cached = cache[steamId64]
    if cached and cached.expiresAt > now then
        return cached.data
    end

    local url = ('https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s')
        :format(Config.Steam.ApiKey, steamId64)

    local p = promise.new()
    PerformHttpRequest(url, function(statusCode, body, headers)
        p:resolve({ statusCode = statusCode, body = body })
    end, 'GET')

    local result = Citizen.Await(p)

    if result.statusCode ~= 200 or not result.body then
        DebugPrint('Steam API fejlede for %s (status %s).', steamId64, tostring(result.statusCode))
        return nil
    end

    local ok, decoded = pcall(json.decode, result.body)
    if not ok or not decoded or not decoded.response or not decoded.response.players or not decoded.response.players[1] then
        DebugPrint('Kunne ikke parse Steam API-svar for %s.', steamId64)
        return nil
    end

    local player = decoded.response.players[1]
    local data = {
        personaname = player.personaname,
        avatarfull  = player.avatarfull,
    }

    cache[steamId64] = { data = data, expiresAt = now + Config.Steam.CacheSeconds }
    return data
end

_G.AdminSteam = Steam
