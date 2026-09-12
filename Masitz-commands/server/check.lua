-- ============================================================
--  Masitz-commands | server/check.lua
--
--  /check [ID] - henter server-side information om en spiller og
--  sender den UDELUKKENDE til Discord (aldrig som chat-besked til den
--  der bruger kommandoen, og slet ikke til target-spilleren selv).
--  Klienten sender kun target-ID'et - alt andet slås op her.
-- ============================================================

--- Synkront (via promise/Citizen.Await) Steam-navneopslag, kun brugt hvis
--- Config.Command.Check.SteamApiKey er sat. Fejler stille (returnerer nil)
--- ved manglende nøgle, netværksfejl eller uventet svar - /check må aldrig
--- crashe eller hænge på grund af et eksternt API.
local function FetchSteamName(steamId64)
    local apiKey = Config.Command.Check.SteamApiKey
    if not apiKey or apiKey == '' then return nil end

    local url = ('https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/?key=%s&steamids=%s')
        :format(apiKey, steamId64)

    local p = promise.new()
    PerformHttpRequest(url, function(statusCode, body)
        p:resolve({ statusCode = statusCode, body = body })
    end, 'GET')

    local result = Citizen.Await(p)
    if result.statusCode ~= 200 or not result.body then return nil end

    local ok, decoded = pcall(json.decode, result.body)
    if not ok or not decoded or not decoded.response or not decoded.response.players
        or not decoded.response.players[1] then
        return nil
    end

    return decoded.response.players[1].personaname
end

local function GetOtherIdentifiers(source)
    local others = {}
    for _, id in ipairs(GetPlayerIdentifiers(source) or {}) do
        if not id:find('^license:') and not id:find('^license2:') and not id:find('^discord:')
            and not id:find('^steam:') and not id:find('^ip:') then
            others[#others + 1] = id
        end
    end
    if #others == 0 then return 'Ingen' end
    return table.concat(others, ', ')
end

local function GetIp(source)
    local endpoint = GetPlayerEndpoint(source)
    if not endpoint then return 'Ikke fundet' end
    return endpoint:match('^([^:]+)') or endpoint
end

RegisterCommand('check', function(source, args)
    if source == 0 then return end
    if not Config.Command.Check.Enabled then return end

    if not Helpers.IsStaff(source, Config.Command.Check) then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Adgang nægtet',
            description = 'Du har ikke tilladelse til at bruge denne kommando.',
            type = 'error',
        })
        return
    end

    local ok, targetId, err = Helpers.ValidateTarget(args[1])
    if not ok then
        TriggerClientEvent('ox_lib:notify', source, { title = 'Check', description = err, type = 'error' })
        return
    end

    local discordId = Helpers.GetDiscordId(targetId)
    local steamHex = Helpers.GetSteamHex(targetId)
    local steamId64 = Helpers.SteamHexToId64(steamHex)
    local steamName = nil

    if steamId64 then
        steamName = FetchSteamName(steamId64)
        if not steamName and Config.Command.Check.SteamApiKey ~= '' then
            steamName = 'Ikke fundet'
        elseif not steamName then
            steamName = 'Ikke hentet (ingen API-nøgle)'
        end
    end

    Discord.LogCheck({
        staffName = GetPlayerName(source) or tostring(source),
        staffServerId = source,
        serverId = targetId,
        playerName = GetPlayerName(targetId),
        ping = GetPlayerPing(targetId) or 0,

        -- Reelt Discord-brugernavn kræver et bot-token (uden for FiveM Lua's
        -- rækkevidde, jf. README) - fallback til ID/link når identifier findes.
        discordName = discordId and 'Ikke tilgængeligt uden Discord-bot (se ID/link)' or nil,
        discordId = discordId,
        discordProfileUrl = discordId and ('https://discord.com/users/' .. discordId) or nil,

        steamName = steamName,
        steamId64 = steamId64,
        steamProfileUrl = steamId64 and ('https://steamcommunity.com/profiles/' .. steamId64) or nil,

        ip = GetIp(targetId),

        license = GetPlayerIdentifierByType(targetId, 'license'),
        license2 = GetPlayerIdentifierByType(targetId, 'license2'),
        otherIdentifiers = GetOtherIdentifiers(targetId),
    })

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Check',
        description = 'Spiller-information er sendt til Discord.',
        type = 'success',
    })
end, false)
