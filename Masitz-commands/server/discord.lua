-- ============================================================
--  Masitz-commands | server/discord.lua
--
--  Ét centralt sted for al Discord-kommunikation:
--   1. Udgående webhook-logging (POV + /check) - ingen
--      PerformHttpRequest-kald spredt ud over resten af resourcen.
--   2. Indgående HTTP-endpoint til automatisk POV-registrering fra en
--      EKSTERN Discord-bot (ingen Discord-bot-integration fandtes i
--      forvejen nogen steder i den eksisterende serverstruktur, jf.
--      gennemgangen - dette er derfor en ny, selvstændig, dokumenteret
--      API-kontrakt. Se README.md for det fulde format).
-- ============================================================

Discord = {}

local COLOR = {
    info = 3447003,     -- blå   - request oprettet
    success = 3066993,  -- grøn  - POV completed
    warning = 15105570, -- orange - anden frist / advarsel
    danger = 15158332,  -- rød   - kick
    ban = 10038562,     -- mørkerød - permanent ban
    neutral = 9807270,  -- grå   - /check, generel info
}
Discord.COLOR = COLOR

local function IsConfigured(webhook)
    return type(webhook) == 'string' and webhook ~= '' and webhook ~= 'DIN_WEBHOOK_HER'
end

--- Sender ét embed til en given webhook. Fejler stille (kun konsol-log)
--- hvis webhooken ikke er sat op eller Discord returnerer en fejl - en
--- manglende/forkert webhook må aldrig kunne crashe en command.
function Discord.Send(webhook, embed, username)
    if not IsConfigured(webhook) then
        Helpers.DebugPrint('Discord-log sprunget over - ingen webhook konfigureret.')
        return
    end

    embed.timestamp = embed.timestamp or os.date('!%Y-%m-%dT%H:%M:%SZ')
    embed.footer = embed.footer or { text = 'Masitz-commands' }

    local payload = json.encode({
        username = username or 'Masitz-commands',
        embeds = { embed },
    })

    PerformHttpRequest(webhook, function(statusCode)
        if statusCode ~= 200 and statusCode ~= 204 then
            print(('^1[Masitz-commands]^7 Discord webhook fejlede med status %s'):format(tostring(statusCode)))
        end
    end, 'POST', payload, { ['Content-Type'] = 'application/json' })
end

local function Field(name, value, inline)
    return { name = name, value = tostring(value ~= nil and value ~= '' and value or 'Ikke fundet'), inline = inline ~= false }
end
Discord.Field = Field

-- ------------------------------------------------------------------
--  POV-LOGGING
--  event: 'created' | 'completed' | 'stage2_warning' | 'kicked' |
--         'banned' | 'povdone_noop' | 'abuse' | 'error'
-- ------------------------------------------------------------------
function Discord.LogPov(event, data)
    local webhook = Config.Command.Pov.Webhook
    local embed

    if event == 'created' then
        embed = {
            title = '📨 POV-anmodning oprettet',
            color = COLOR.info,
            fields = {
                Field('Request-ID', data.requestId),
                Field('Anmoder', ('%s (ID: %s)'):format(data.requesterName, data.requesterServerId)),
                Field('Mål', ('%s (ID: %s)'):format(data.targetName, data.targetServerId)),
                Field('Discord-ID (mål)', data.targetDiscordId or 'Ikke fundet'),
                Field('Gentagelses-anmodning', data.isRepeat and 'Ja (skærpet 20 min. frist)' or 'Nej'),
                Field('Frist', data.isRepeat
                    and (Config.Command.Pov.RepeatTimeout .. ' minutter (permanent ban ved overskridelse)')
                    or (Config.Command.Pov.FirstTimeout .. ' + ' .. Config.Command.Pov.SecondTimeout .. ' minutter')),
            },
        }
    elseif event == 'completed' then
        embed = {
            title = '✅ POV registreret',
            color = COLOR.success,
            fields = {
                Field('Request-ID', data.requestId),
                Field('Spiller', ('%s (ID: %s)'):format(data.targetName, tostring(data.targetServerId or '—'))),
                Field('Metode', data.method == 'auto' and 'Automatisk (Discord-bot)' or 'Manuel (/povdone)'),
                Field('Godkendt af', data.staffName or 'N/A (automatisk)'),
            },
        }
    elseif event == 'stage2_warning' then
        embed = {
            title = '⏰ Første frist udløbet - anden frist startet',
            color = COLOR.warning,
            fields = {
                Field('Request-ID', data.requestId),
                Field('Spiller', ('%s (ID: %s)'):format(data.targetName, tostring(data.targetServerId or '—'))),
                Field('Ny frist', Config.Command.Pov.SecondTimeout .. ' minutter'),
            },
        }
    elseif event == 'kicked' then
        embed = {
            title = '👢 Spiller kicked - POV ikke indsendt',
            color = COLOR.danger,
            fields = {
                Field('Request-ID', data.requestId),
                Field('Spiller', ('%s (ID: %s)'):format(data.targetName, tostring(data.targetServerId or '—'))),
                Field('Discord-ID', data.targetDiscordId),
                Field('Årsag', Config.Command.Pov.KickReason),
                Field('Oprettet', data.createdAt),
                Field('Kicked', os.date('%Y-%m-%d %H:%M:%S')),
            },
        }
    elseif event == 'banned' then
        embed = {
            title = '⛔ PERMANENT BAN - gentaget manglende POV',
            color = COLOR.ban,
            fields = {
                Field('Request-ID', data.requestId),
                Field('Spiller', ('%s (ID: %s)'):format(data.targetName, tostring(data.targetServerId or '—'))),
                Field('Identifier', data.targetIdentifier),
                Field('Discord-ID', data.targetDiscordId),
                Field('Årsag', Config.Command.Pov.BanReason),
            },
        }
    elseif event == 'povdone_noop' then
        embed = {
            title = 'ℹ️ /povdone brugt uden aktiv anmodning',
            color = COLOR.neutral,
            fields = {
                Field('Brugt af', ('%s (ID: %s)'):format(data.staffName, data.staffServerId)),
                Field('Målt spiller', ('ID: %s'):format(data.targetServerId)),
            },
        }
    elseif event == 'abuse' then
        embed = {
            title = '🚨 Muligt misbrug opdaget',
            color = COLOR.danger,
            fields = {
                Field('Spiller', ('ID: %s'):format(data.serverId)),
                Field('Handling', data.reason),
            },
        }
    elseif event == 'error' then
        embed = {
            title = '⚠️ Fejl i POV-systemet',
            color = COLOR.danger,
            fields = { Field('Detaljer', data.message) },
        }
    else
        return
    end

    Discord.Send(webhook, embed)
end

-- ------------------------------------------------------------------
--  INDGÅENDE HTTP-ENDPOINT — automatisk POV-registrering fra en
--  ekstern Discord-bot. Se README.md for det fulde kontrakt-format
--  (URL, headers, body, svarkoder).
--
--  BEMÆRK: FXServer tillader kun ÉT globalt SetHttpHandler pr. server.
--  Har I allerede et andet resource der kalder SetHttpHandler, vil de
--  kollidere - kun det senest startede resource's handler er aktiv.
-- ------------------------------------------------------------------
local function RespondJson(res, status, body)
    res.writeHead(status, { ['Content-Type'] = 'application/json' })
    res.send(json.encode(body))
end

local function HandlePovCompleteRequest(req, res)
    if req.method ~= 'POST' then
        RespondJson(res, 405, { ok = false, error = 'method_not_allowed' })
        return
    end

    local providedSecret = req.headers['x-masitz-secret'] or req.headers['X-Masitz-Secret']
    local expectedSecret = Config.Command.Pov.DiscordApi.SharedSecret
    if not expectedSecret or expectedSecret == '' or expectedSecret == 'SÆT_EN_LANG_TILFÆLDIG_HEMMELIGHED_HER' then
        print('^1[Masitz-commands]^7 Discord POV-API blev kaldt, men SharedSecret er ikke konfigureret - afvist.')
        RespondJson(res, 503, { ok = false, error = 'not_configured' })
        return
    end
    if not providedSecret or providedSecret ~= expectedSecret then
        RespondJson(res, 401, { ok = false, error = 'unauthorized' })
        return
    end

    req.setDataHandler(function(body)
        local ok, decoded = pcall(json.decode, body)
        if not ok or type(decoded) ~= 'table' or type(decoded.discordId) ~= 'string' or decoded.discordId == '' then
            RespondJson(res, 400, { ok = false, error = 'invalid_body' })
            return
        end

        -- Al reel logik (opslag, verificering, completion) ligger i
        -- Pov.CompleteByDiscordId - denne fil ved intet om POV-state,
        -- den er ren transport.
        local success, resultCode = Pov.CompleteByDiscordId(decoded.discordId)

        if success then
            RespondJson(res, 200, { ok = true })
        elseif resultCode == 'not_found' then
            RespondJson(res, 404, { ok = false, error = 'no_active_request_for_discord_id' })
        else
            RespondJson(res, 500, { ok = false, error = 'internal_error' })
        end
    end)
end

if Config.Command.Pov.DiscordApi and Config.Command.Pov.DiscordApi.Enabled then
    SetHttpHandler(function(req, res)
        if req.path == Config.Command.Pov.DiscordApi.HttpPath then
            HandlePovCompleteRequest(req, res)
        else
            res.writeHead(404, { ['Content-Type'] = 'application/json' })
            res.send(json.encode({ ok = false, error = 'not_found' }))
        end
    end)
end

-- ------------------------------------------------------------------
--  /check-LOGGING
-- ------------------------------------------------------------------
function Discord.LogCheck(data)
    local webhook = Config.Command.Check.Webhook

    local embed = {
        title = '🔍 Spiller-check',
        color = COLOR.neutral,
        fields = {
            Field('👮 Udført af', ('%s (ID: %s)'):format(data.staffName, data.staffServerId)),
            Field('🖥️ Server-ID', data.serverId, true),
            Field('🎮 FiveM-navn', data.playerName, true),
            Field('📶 Ping', data.ping .. ' ms', true),

            Field('💬 Discord-navn', data.discordName, true),
            Field('💬 Discord-ID', data.discordId, true),
            Field('💬 Discord-profil', data.discordProfileUrl, false),

            Field('🎮 Steam-navn', data.steamName, true),
            Field('🎮 Steam-ID64', data.steamId64, true),
            Field('🎮 Steam-profil', data.steamProfileUrl, false),

            Field('🌐 IP-adresse', data.ip, false),

            Field('🪪 License', data.license, true),
            Field('🪪 License2', data.license2, true),
            Field('🪪 Andre identifiers', data.otherIdentifiers, false),
        },
        footer = { text = 'Masitz-commands · /check' },
    }

    Discord.Send(webhook, embed)
end
