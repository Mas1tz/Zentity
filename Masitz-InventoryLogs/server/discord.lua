-- ============================================================
--  Masitz-InventoryLogs | server/discord.lua
--  Webhook routing, embed construction and a rate-limited, retrying,
--  per-webhook queue so Discord can never slow down or block
--  ox_inventory. If Discord is unreachable, entries simply pile up
--  (capped) and get dropped/summarized - inventory keeps working.
-- ============================================================

Discord = {}

---@class DiscordQueue
---@field entries table[]
---@field running boolean
---@field overflow number

---@type table<string, DiscordQueue>
local queues = {}

local ACTION_META = {
    give                = { title = '🎁 Item Given',        color = 'give' },
    drop                = { title = '🗑️ Item Drop',         color = 'drop' },
    pickup              = { title = '📥 Item Pickup',        color = 'pickup' },
    stash_deposit       = { title = '🗄️ Stash Deposit',      color = 'stash' },
    stash_withdraw      = { title = '🗄️ Stash Withdraw',     color = 'stash' },
    trunk_deposit       = { title = '🚗 Trunk Deposit',      color = 'vehicle' },
    trunk_withdraw      = { title = '🚗 Trunk Withdraw',     color = 'vehicle' },
    glovebox_deposit    = { title = '🚘 Glovebox Deposit',   color = 'vehicle' },
    glovebox_withdraw   = { title = '🚘 Glovebox Withdraw',  color = 'vehicle' },
    container_store     = { title = '📦 Container Store',    color = 'stash' },
    container_retrieve  = { title = '📦 Container Retrieve', color = 'stash' },
    evidence_deposit    = { title = '🚔 Evidence Deposit',   color = 'evidence' },
    evidence_withdraw   = { title = '🚔 Evidence Withdraw',  color = 'evidence' },
    dumpster_deposit    = { title = '🗑️ Dumpster Deposit',   color = 'drop' },
    dumpster_retrieve   = { title = '🗑️ Dumpster Retrieve',  color = 'drop' },
    inventory_swap      = { title = '🔄 Item Swap',          color = 'give' },
    inventory_stack     = { title = '📚 Stack Merge',        color = 'give' },
    inventory_transfer  = { title = '🔄 Inventory Transfer', color = 'give' },
    move_slot           = { title = '📦 Slot Move',          color = 'give' },
    split_stack         = { title = '✂️ Stack Split',        color = 'give' },
    shop_purchase       = { title = '🏪 Shop Purchase',      color = 'shop' },
    open_shop           = { title = '🏪 Shop Opened',        color = 'shop' },
    craft               = { title = '🛠️ Item Crafted',       color = 'crafting' },
    use_item            = { title = '💊 Item Used',          color = 'give' },
    open_inventory      = { title = '🔓 Inventory Opened',   color = 'admin' },
}

local function resolveWebhookUrl(category)
    local url = Config.Webhooks[category]
    if not url or url == '' then
        url = Config.Webhooks.default
    end
    if not url or url == '' then return nil end
    return url
end

---@param action string
---@return string?
function Discord.GetWebhookForAction(action)
    local category = Config.ActionWebhooks[action] or 'default'
    return resolveWebhookUrl(category)
end

local function playerField(info, label)
    if not info then return nil end
    local display = info.charName or info.name or 'Unknown'
    local lines = { ('**%s**'):format(display) }

    if info.source then
        lines[#lines + 1] = ('Server ID: `%s`'):format(info.source)
    end

    if Config.PlayerInfo.includeIdentifier and info.identifier then
        lines[#lines + 1] = ('Identifier: `%s`'):format(info.identifier)
    end

    if Config.PlayerInfo.includeJob and info.job then
        local jobLine = info.jobLabel or info.job
        if Config.PlayerInfo.includeGrade and info.gradeLabel then
            jobLine = ('%s (%s)'):format(jobLine, info.gradeLabel)
        elseif Config.PlayerInfo.includeGrade and info.grade then
            jobLine = ('%s (grade %s)'):format(jobLine, info.grade)
        end
        lines[#lines + 1] = ('Job: %s'):format(jobLine)
    end

    return { name = label, value = table.concat(lines, '\n'), inline = true }
end

local function inventoryLabel(side)
    if not side then return nil end
    local label = Utils.InventoryTypeLabel(side.type)
    if side.friendlyLabel and side.friendlyLabel ~= '' then
        label = ('%s (%s)'):format(label, side.friendlyLabel)
    end
    if side.id and side.type ~= 'player' then
        label = ('%s - `%s`'):format(label, tostring(side.id))
    end
    if side.slot then
        label = ('%s, slot %s'):format(label, tostring(side.slot))
    end
    return label
end

---Builds a single Discord embed from a normalized log entry produced by
---server/logger.lua. Every field is optional and only rendered when the
---entry actually carries that information - nothing is invented.
---@param entry table
---@return table
function Discord.BuildEmbed(entry)
    local meta = ACTION_META[entry.action] or { title = entry.action, color = 'admin' }
    local fields = {}

    local function addField(name, value, inline)
        if value == nil or value == '' then return end
        fields[#fields + 1] = { name = name, value = tostring(value), inline = inline ~= false }
    end

    local playerLabel = entry.action == 'give' and '👤 Player (Sender)' or '👤 Player'
    local pf = playerField(entry.player, playerLabel)
    if pf then fields[#fields + 1] = pf end

    if entry.target then
        local tf = playerField(entry.target, '🎯 Target')
        if tf then fields[#fields + 1] = tf end
    end

    if entry.item then
        addField('📦 Item', ('%s'):format(entry.item.label or entry.item.name), true)
        if entry.item.name and entry.item.label and entry.item.name ~= entry.item.label then
            addField('🔖 Item ID', ('`%s`'):format(entry.item.name), true)
        end
        addField('🔢 Amount', entry.item.amount, true)
    end

    if entry.from then addField('📤 From', inventoryLabel(entry.from), true) end
    if entry.to then addField('📥 To', inventoryLabel(entry.to), true) end

    if entry.vehicle then addField('🚙 Vehicle Plate', ('`%s`'):format(entry.vehicle), true) end
    if entry.stash then addField('🗄️ Stash ID', ('`%s`'):format(entry.stash), true) end

    if entry.shop then
        addField('🏪 Shop', entry.shop.label or entry.shop.id, true)
        if entry.shop.price then
            addField('💰 Price', ('%s %s'):format(entry.shop.price, entry.shop.currency or 'money'), true)
        end
    end

    if entry.recipe then
        addField('🧾 Recipe', entry.recipe.name, true)
        if entry.recipe.bench then addField('🛠️ Bench', entry.recipe.bench, true) end
    end

    if Config.PlayerInfo.includeCoords and entry.coords then
        addField('📍 Position', Utils.FormatCoords(entry.coords), true)
    end

    if entry.metadataText then
        addField('🧬 Metadata', ('```json\n%s\n```'):format(entry.metadataText), false)
    end

    if entry.note then
        addField('ℹ️ Note', entry.note, false)
    end

    addField('🕐 Time', Utils.FormatTimestamp(entry.timestamp), true)

    return {
        title = meta.title,
        color = Config.Colors[meta.color] or Config.Colors.admin,
        fields = fields,
        footer = { text = Config.Discord.footer },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ', entry.timestamp or os.time()),
    }
end

-- ------------------------------------------------------------
--  Queue + rate-limited dispatch
-- ------------------------------------------------------------

local function getQueue(url)
    local queue = queues[url]
    if not queue then
        queue = { entries = {}, running = false, overflow = 0 }
        queues[url] = queue
    end
    return queue
end

local function buildPayload(embed)
    return json.encode({
        username = Config.Discord.username,
        avatar_url = (Config.Discord.avatar ~= '' and Config.Discord.avatar) or nil,
        embeds = { embed },
    })
end

local function summaryEmbed(count)
    return {
        title = 'ℹ️ Log Summary',
        description = ('%d additional inventory action(s) occurred while the log queue was full and have been collapsed into this message.'):format(count),
        color = Config.Colors.warning,
        footer = { text = Config.Discord.footer },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
end

local function sendWithRetry(url, embed, attempt)
    attempt = attempt or 1

    PerformHttpRequest(url, function(statusCode, body)
        if statusCode == 200 or statusCode == 204 then
            Utils.DebugPrint('Discord webhook delivered.')
            return
        end

        if statusCode == 429 then
            local retryAfterMs = 1000
            if body then
                local ok, decoded = pcall(json.decode, body)
                if ok and type(decoded) == 'table' and decoded.retry_after then
                    retryAfterMs = math.floor(decoded.retry_after * 1000) + 50
                end
            end

            if attempt <= Config.Discord.RateLimit.maxRetries then
                Utils.DebugPrint(('Discord rate limited, retrying in %dms (attempt %d).'):format(retryAfterMs, attempt))
                SetTimeout(retryAfterMs, function()
                    sendWithRetry(url, embed, attempt + 1)
                end)
            else
                Utils.Warn('Dropped a Discord log after repeated rate limiting (429).')
            end
            return
        end

        if attempt <= Config.Discord.RateLimit.maxRetries then
            local backoff = Config.Discord.RateLimit.retryBackoffMs * attempt
            Utils.DebugPrint(('Discord request failed (status %s), retrying in %dms.'):format(tostring(statusCode), backoff))
            SetTimeout(backoff, function()
                sendWithRetry(url, embed, attempt + 1)
            end)
        else
            Utils.Warn(('Dropped a Discord log after repeated failures (last status %s). ox_inventory is unaffected.'):format(tostring(statusCode)))
        end
    end, 'POST', buildPayload(embed), { ['Content-Type'] = 'application/json' })
end

local function runDispatcher(url)
    local queue = getQueue(url)
    if queue.running then return end
    queue.running = true

    CreateThread(function()
        while true do
            local embed = table.remove(queue.entries, 1)

            if not embed then
                if queue.overflow > 0 then
                    local overflow = queue.overflow
                    queue.overflow = 0
                    sendWithRetry(url, summaryEmbed(overflow))
                    Wait(Config.Discord.RateLimit.minIntervalMs)
                end
                queue.running = false
                break
            end

            sendWithRetry(url, embed)
            Wait(Config.Discord.RateLimit.minIntervalMs)
        end
    end)
end

---Queues an already-built embed for delivery to a specific webhook URL.
---Never blocks - this is a plain table insert plus, at most, kicking off a
---dispatcher thread if one isn't already running for this webhook.
---@param url string?
---@param embed table
function Discord.Enqueue(url, embed)
    if not Config.Discord.enabled or not url then return end

    local queue = getQueue(url)

    if #queue.entries >= Config.Discord.Queue.maxSize then
        if Config.Discord.Queue.overflowStrategy == 'summary' then
            queue.overflow = queue.overflow + 1
        end
        -- overflowStrategy 'drop' (or default) just silently discards the entry
        return
    end

    queue.entries[#queue.entries + 1] = embed

    if not queue.running then
        runDispatcher(url)
    end
end

---Convenience entry point used by logger.lua: builds the embed and routes
---it to the correct webhook for the entry's action in one call.
---@param entry table
function Discord.Log(entry)
    if not Config.Discord.enabled then return end
    if Config.Storage == 'database' then return end

    local url = Discord.GetWebhookForAction(entry.action)
    if not url then return end

    Discord.Enqueue(url, Discord.BuildEmbed(entry))
end
