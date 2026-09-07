-- ============================================================
--  mm-adminpakke V2 | server/logs.lua
-- ============================================================

local Logs = {}

local function FormatBasket(basket)
    local lines = {}
    for _, entry in ipairs(basket) do
        lines[#lines + 1] = ('%s x%d'):format(entry.name, entry.amount)
    end
    return table.concat(lines, ', ')
end

function Logs.Console(adminName, adminId, targetName, targetId, basket)
    if not Config.Logging.Console then return end
    print(('^2[mm-adminpakke LOG]^7 Admin: %s (%d) -> Target: %s (%d) | Items: %s | Tid: %s'):format(
        adminName, adminId, targetName, targetId, FormatBasket(basket), os.date('%Y-%m-%d %H:%M:%S')
    ))
end

function Logs.Discord(adminName, adminId, targetName, targetId, basket)
    if not Config.Logging.Discord then return end
    if not Config.DiscordWebhook or Config.DiscordWebhook == '' or Config.DiscordWebhook == 'YOUR_WEBHOOK_URL_HERE' then return end

    local embed = {
        title = '📋 Admin Give Log',
        color = Config.DiscordEmbed.Color,
        fields = {
            { name = '👮 Admin',  value = ('**%s** (ID: %d)'):format(adminName, adminId), inline = true },
            { name = '🎯 Target', value = ('**%s** (ID: %d)'):format(targetName, targetId), inline = true },
            { name = '📦 Items',  value = '```' .. FormatBasket(basket) .. '```', inline = false },
            { name = '⏰ Tid',    value = os.date('%Y-%m-%d %H:%M:%S'), inline = true },
        },
        footer = { text = 'mm-adminpakke V2' },
    }

    local payload = json.encode({
        username = Config.DiscordEmbed.Username,
        avatar_url = Config.DiscordEmbed.AvatarUrl,
        embeds = { embed },
    })

    PerformHttpRequest(Config.DiscordWebhook, function(statusCode)
        if statusCode ~= 204 and statusCode ~= 200 then
            print('^1[mm-adminpakke]^7 Discord webhook fejlede: ' .. tostring(statusCode))
        end
    end, 'POST', payload, { ['Content-Type'] = 'application/json' })
end

function Logs.Log(adminName, adminId, targetName, targetId, basket)
    Logs.Console(adminName, adminId, targetName, targetId, basket)
    Logs.Discord(adminName, adminId, targetName, targetId, basket)
end

_G.AdminLogs = Logs
