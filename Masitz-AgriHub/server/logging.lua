-- ============================================================
--  Masitz-AgriHub | server/logging.lua
--  Discord webhook-dispatch + DB audit-log. Webhook-URLs ligger
--  UDELUKKENDE i config.lua (server-side) — sendes ALDRIG til
--  klienten/NUI'en. Se §118.
-- ============================================================

AH = AH or {}

local function ResolveWebhook(kind)
    if not Config.Agri.Logging or not Config.Agri.Logging.enabled then return nil end
    local url = Config.Agri.Logging.webhooks and Config.Agri.Logging.webhooks[kind]
    if not url or url == '' then return nil end
    return url
end

local function SendWebhook(kind, title, color, fields)
    local url = ResolveWebhook(kind)
    if not url then return end

    local embedFields = {}
    for _, f in ipairs(fields) do
        embedFields[#embedFields + 1] = {
            name   = f[1],
            value  = tostring(f[2] ~= nil and f[2] ~= '' and f[2] or 'n/a'),
            inline = f[3] ~= false,
        }
    end

    local payload = {
        username = Config.Agri.Logging.username or 'AgriHub',
        embeds = {
            {
                title     = title,
                color     = color,
                fields    = embedFields,
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                footer    = { text = 'Masitz-AgriHub' },
            },
        },
    }

    PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

-- ─── DB AUDIT LOG (uafhængig af om Discord-logging er slået til) ──
function AH.DbLog(action, identifier, discordId, playerName, data)
    local ok, err = pcall(function()
        MySQL.insert('INSERT INTO agrihub_logs (action, identifier, discord_id, player_name, data) VALUES (?,?,?,?,?)',
            { action, identifier, discordId, playerName, json.encode(data or {}) })
    end)
    if not ok then
        AH.Log('DbLog fejlede for action=%s: %s', tostring(action), tostring(err))
    end
end

-- ─── GENERISK ACTION-LOG (DB + valgfri webhook-kategori) ──────────
function AH.LogAction(webhookKind, action, src, data)
    data = data or {}
    local xp = src and AH.GetXPlayer(src)
    local identifier = (xp and xp.identifier) or data.identifier
    local discordId  = (src and AH.GetDiscordId(src)) or data.discordId
    local playerName = (xp and xp.getName()) or data.playerName or 'Ukendt'

    AH.DbLog(action, identifier, discordId, playerName, data)

    local fields = {
        { 'Spiller',     playerName,          true },
        { 'Identifier',  identifier or 'n/a', true },
    }
    for k, v in pairs(data) do
        if type(v) ~= 'table' then
            fields[#fields + 1] = { k, tostring(v), true }
        end
    end
    fields[#fields + 1] = { 'Tidspunkt', os.date('%Y-%m-%d %H:%M:%S'), false }

    SendWebhook(webhookKind, action, 0x4c6ef5, fields)
end

-- ─── SIKKERHEDSLOG (§105, §113) — altid printet til konsol, uanset
--     webhook-konfiguration. ──────────────────────────────────────
function AH.LogSecurity(src, code, message, data)
    data = data or {}
    local xp = src and AH.GetXPlayer(src)
    local identifier = (xp and xp.identifier) or 'ukendt'
    local discordId  = (src and AH.GetDiscordId(src)) or 'ukendt'
    local playerName = (xp and xp.getName()) or ('source ' .. tostring(src))

    AH.DbLog('SECURITY_' .. code, identifier, discordId, playerName, data)

    local fields = {
        { 'Spiller',    playerName,           true },
        { 'Server ID',  tostring(src or '?'), true },
        { 'Identifier', identifier,           true },
        { 'Discord ID', discordId,            true },
        { 'Kode',       code,                 false },
        { 'Besked',     message,              false },
    }
    for k, v in pairs(data) do
        if type(v) ~= 'table' then
            fields[#fields + 1] = { k, tostring(v), true }
        end
    end

    SendWebhook('security', '🚨 SECURITY ALERT', 0xe03131, fields)
    print(('^1[Masitz-AgriHub SECURITY]^7 %s (src=%s, code=%s): %s'):format(playerName, tostring(src), code, message))
end
