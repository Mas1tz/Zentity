-- ══════════════════════════════════════════════════════════
--  PROFILE AVATAR — mm-christmas
--
--  Løser Steam/Discord avatar-URLs SERVER-SIDE. Config.ProfileImage's
--  steamApiKey/discordBotToken bruges KUN i denne fil og forlader
--  aldrig serveren - kun det færdige (offentlige) avatar-billede-link
--  sendes videre til NUI, som loader billedet direkte fra
--  Steam/Discords egne CDN'er.
--
--  Cache: pr.-identifier (overlever reconnects indenfor TTL). Et
--  mislykket API-kald cachelagres kort (60s) som "intet fundet" for
--  ikke at hamre en fejlende API igen og igen - fejl her må ALDRIG
--  ødelægge eller blokere UI'en, kun falde tilbage til default avatar.
-- ══════════════════════════════════════════════════════════

Avatar = {}

local cache = {} -- [providerKey] = { url = string|nil, expires = osTimeSeconds }

local function nowSeconds() return os.time() end

local function httpGet(url, headers)
    local p = promise.new()
    PerformHttpRequest(url, function(status, body)
        p:resolve({ status = status, body = body })
    end, 'GET', '', headers or {})

    local ok, res = pcall(Citizen.Await, p)
    if not ok then return nil end
    return res
end

local function fetchSteamAvatar(steamHex)
    local key = Config.ProfileImage.steamApiKey
    if not key or key == '' then return nil end

    local steamId64 = tonumber(steamHex, 16)
    if not steamId64 then return nil end

    local url = ('https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s')
        :format(key, tostring(steamId64))

    local res = httpGet(url)
    if not res or res.status ~= 200 or not res.body then return nil end

    local ok, data = pcall(json.decode, res.body)
    if not ok or not data or not data.response or not data.response.players or not data.response.players[1] then
        return nil
    end

    return data.response.players[1].avatarfull
end

local function fetchDiscordAvatar(discordId)
    local token = Config.ProfileImage.discordBotToken
    if not token or token == '' then return nil end

    local url = ('https://discord.com/api/v10/users/%s'):format(discordId)
    local res = httpGet(url, { ['Authorization'] = 'Bot ' .. token })
    if not res or res.status ~= 200 or not res.body then return nil end

    local ok, data = pcall(json.decode, res.body)
    if not ok or not data then return nil end

    if data.avatar then
        local ext = (data.avatar:sub(1, 2) == 'a_') and 'gif' or 'png'
        return ('https://cdn.discordapp.com/avatars/%s/%s.%s?size=128'):format(discordId, data.avatar, ext)
    end

    -- Ingen avatar sat — brug Discords eget default-avatar-system.
    local idNum = tonumber(discordId)
    local idx   = idNum and math.floor((idNum // 4194304) % 6) or 0
    return ('https://cdn.discordapp.com/embed/avatars/%d.png'):format(idx)
end

local function cachedOrFetch(cacheKey, fetchFn, ...)
    local cached = cache[cacheKey]
    if cached and cached.expires > nowSeconds() then
        return cached.url
    end

    local args = { ... }
    local ok, url = pcall(function() return fetchFn(table.unpack(args)) end)

    if ok and url then
        cache[cacheKey] = { url = url, expires = nowSeconds() + (Config.ProfileImage.cacheTime or 3600) }
        return url
    end

    -- Negativt cache-hit (kort TTL) så en fejlende API ikke hamres.
    cache[cacheKey] = { url = nil, expires = nowSeconds() + 60 }
    if not ok then
        Shared.Debug('Avatar fetch fejlede:', tostring(url))
    end
    return nil
end

-- Returnerer en avatar-URL (string) eller nil hvis ingen kunne findes -
-- klienten viser sit lokale default julemand-ikon i så fald.
function Avatar.Get(src)
    local provider = Config.ProfileImage.provider

    if provider == 'none' then return nil end

    local discordId = GetPlayerIdentifierByType(src, 'discord')
    local steamId    = GetPlayerIdentifierByType(src, 'steam')

    local order
    if provider == 'discord' then
        order = { 'discord' }
    elseif provider == 'steam' then
        order = { 'steam' }
    else
        order = { 'discord', 'steam' } -- 'auto'
    end

    for _, p in ipairs(order) do
        if p == 'discord' and discordId then
            local id  = discordId:gsub('^discord:', '')
            local url = cachedOrFetch('discord:' .. id, fetchDiscordAvatar, id)
            if url then return url end
        elseif p == 'steam' and steamId then
            local hex = steamId:gsub('^steam:', '')
            local url = cachedOrFetch('steam:' .. hex, fetchSteamAvatar, hex)
            if url then return url end
        end
    end

    return nil
end
