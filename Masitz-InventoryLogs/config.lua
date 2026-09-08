Config = {}

-- ============================================================
--  DEBUG
--  When false, the console stays completely clean - no hook
--  firing spam, no queue diagnostics. Only real warnings/errors
--  (e.g. a webhook rejecting a request) are ever printed
--  regardless of this setting.
-- ============================================================
Config.Debug = false

-- ============================================================
--  STORAGE
--  'discord'  -> Discord embeds only, no database required at all
--  'database' -> oxmysql only, no Discord requests are sent
--  'both'     -> both destinations
-- ============================================================
Config.Storage = 'discord'

Config.Database = {
    tableName = 'masitz_inventory_logs',
    retentionDays = 30,            -- rows older than this are deleted automatically (0 = keep forever)
    cleanupIntervalMinutes = 60,   -- how often the retention sweep runs
    cleanupBatchSize = 500,        -- rows deleted per DELETE statement, keeps locks short
}

-- ============================================================
--  DISCORD
-- ============================================================
Config.Discord = {
    enabled = true,
    username = 'Masitz Inventory Logs',
    avatar = '',
    footer = 'Masitz Inventory Logs',

    -- Discord effectively allows ~5 requests / 2s per webhook. We pace well
    -- under that and honour 429 responses with their own retry_after value.
    RateLimit = {
        minIntervalMs = 350,   -- minimum spacing between two requests on the SAME webhook
        maxRetries = 3,        -- retries on a 429 / network failure before the entry is dropped
        retryBackoffMs = 1000, -- base backoff, doubled on each retry on top of Discord's retry_after
    },

    -- Protects ox_inventory from ever being slowed down by a Discord outage
    -- or a burst of >100 actions at once: entries pile up in memory instead
    -- of blocking, and once the queue is "too full" we stop enqueueing raw
    -- entries and instead collapse everything into a periodic summary.
    Queue = {
        maxSize = 500,              -- hard cap on queued-but-unsent Discord messages per webhook
        overflowStrategy = 'summary', -- 'summary' (send "+N more actions") or 'drop'
    },
}

-- Webhook URLs per category. Config.ActionWebhooks below decides which of
-- these a given action uses. Leave any of these empty to fall back to
-- Config.Webhooks.default; if default is also empty, that category is
-- silently skipped (no error spam).
Config.Webhooks = {
    default   = '',
    player    = '', -- give / receive / player<->player transfers
    drop      = '', -- ground drops, pickups, dumpsters
    stash     = '', -- stashes, containers, police evidence
    vehicle   = '', -- trunk / glovebox
    shop      = '', -- shop purchases
    crafting  = '', -- crafting bench
    admin     = '', -- inventory-open/access audit (off by default, see Config.Logging)
}

-- Maps every action key this resource can produce to one of the webhook
-- categories above. You can freely repoint any action to any category
-- without touching code.
Config.ActionWebhooks = {
    give               = 'player',
    drop               = 'drop',
    pickup             = 'drop',
    stash_deposit      = 'stash',
    stash_withdraw     = 'stash',
    trunk_deposit      = 'vehicle',
    trunk_withdraw     = 'vehicle',
    glovebox_deposit   = 'vehicle',
    glovebox_withdraw  = 'vehicle',
    container_store    = 'stash',
    container_retrieve = 'stash',
    evidence_deposit   = 'stash',
    evidence_withdraw  = 'stash',
    dumpster_deposit   = 'drop',
    dumpster_retrieve  = 'drop',
    inventory_swap     = 'player',
    inventory_stack    = 'player',
    inventory_transfer = 'player',
    move_slot          = 'player',
    split_stack        = 'player',
    shop_purchase      = 'shop',
    open_shop          = 'shop',
    craft              = 'crafting',
    use_item           = 'player',
    open_inventory     = 'admin',
}

-- ============================================================
--  LOGGING TOGGLES
--  Master on/off switch per action. Actions that fire extremely
--  often and rarely matter for an audit trail (stack merges,
--  same-inventory slot moves, item usage, inventory opens) are
--  OFF by default to keep logs meaningful - turn them on if you
--  actually want that volume.
-- ============================================================
Config.Logging = {
    give               = true,
    drop               = true,
    pickup             = true,
    stashDeposit       = true,
    stashWithdraw      = true,
    trunkDeposit       = true,
    trunkWithdraw      = true,
    gloveboxDeposit    = true,
    gloveboxWithdraw   = true,
    containerTransfer  = true,
    evidenceTransfer   = true,
    dumpsterTransfer   = true,
    inventorySwap      = true,
    inventoryTransfer  = true,
    shopPurchase       = true,
    craft              = true,

    -- noisy / opt-in
    inventoryStack     = false, -- merging a stack into a matching slot
    moveSlot           = false, -- moving a full stack to an empty slot in the SAME inventory (bag reorganizing)
    splitStack         = false, -- splitting part of a stack into a new slot
    useItem            = false, -- every item consumption/use (eating, drinking, bandages, ...)
    openShop           = false, -- opening a shop menu (not purchases - those are shopPurchase)
    openInventoryAccess = false, -- opening ANY stash/trunk/glovebox/container/evidence, even without moving items
}

-- ============================================================
--  PLAYER INFORMATION
-- ============================================================
Config.PlayerInfo = {
    includeIdentifier = true,  -- ESX license identifier
    includeJob        = true,  -- job name + label
    includeGrade       = true,  -- job grade + grade label
    includeCoords      = true,  -- player position at the time of the action (drop/pickup only)
}

-- ============================================================
--  METADATA HANDLING
--  Item metadata can be arbitrarily large/ugly (serials, weapon
--  components, custom fields). We JSON-encode it but always cap
--  the size so a single item never breaks a Discord embed.
-- ============================================================
Config.Metadata = {
    enabled = true,
    maxLength = 400, -- characters, after which the encoded metadata is truncated with "..."
}

-- ============================================================
--  DUPLICATE PROTECTION
--  Short-lived fingerprint cache. Defense in depth: our hook
--  registration architecture only fires once per real action, but
--  this guards against double-registration bugs, resource restart
--  edge cases, or a future ox_inventory version changing behaviour.
-- ============================================================
Config.DedupWindowMs = 1500

-- ============================================================
--  EMBED COLORS (decimal, not hex string)
-- ============================================================
Config.Colors = {
    give      = 3447003,  -- blue
    drop      = 15105570, -- orange
    pickup    = 3066993,  -- green
    stash     = 10181046, -- purple
    vehicle   = 15844367, -- gold
    evidence  = 15277667, -- pink/red
    shop      = 2067276,  -- teal
    crafting  = 3426654,  -- dark teal
    admin     = 9807270,  -- gray
    warning   = 15158332, -- red
}
