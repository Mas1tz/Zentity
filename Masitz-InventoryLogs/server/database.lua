-- ============================================================
--  Masitz-InventoryLogs | server/database.lua
--  Optional oxmysql storage. Every function here is a no-op when
--  Config.Storage == 'discord', so this resource works fine on a
--  server that doesn't run oxmysql at all in that mode.
-- ============================================================

Database = {}

local function storageEnabled()
    return Config.Storage == 'database' or Config.Storage == 'both'
end

local function tableName()
    return Config.Database.tableName or 'masitz_inventory_logs'
end

if storageEnabled() then
    if not MySQL then
        Utils.Warn('Config.Storage requires oxmysql, but the MySQL global is not available. Install/start oxmysql, or set Config.Storage to "discord".')
    else
        MySQL.ready(function()
            MySQL.query(([[
                CREATE TABLE IF NOT EXISTS `%s` (
                    `id`                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    `action`              VARCHAR(32)   NOT NULL,
                    `source`              INT UNSIGNED  NULL,
                    `identifier`          VARCHAR(64)   NULL,
                    `player_name`         VARCHAR(100)  NULL,
                    `character_name`      VARCHAR(100)  NULL,
                    `job_name`            VARCHAR(50)   NULL,
                    `job_grade`           INT           NULL,
                    `target_source`       INT UNSIGNED  NULL,
                    `target_identifier`   VARCHAR(64)   NULL,
                    `target_name`         VARCHAR(100)  NULL,
                    `item_name`           VARCHAR(64)   NULL,
                    `item_label`          VARCHAR(100)  NULL,
                    `amount`              INT           NULL,
                    `from_inventory_id`   VARCHAR(100)  NULL,
                    `from_inventory_type` VARCHAR(32)   NULL,
                    `from_slot`           INT           NULL,
                    `to_inventory_id`     VARCHAR(100)  NULL,
                    `to_inventory_type`   VARCHAR(32)   NULL,
                    `to_slot`             INT           NULL,
                    `stash_id`            VARCHAR(100)  NULL,
                    `vehicle_plate`       VARCHAR(16)   NULL,
                    `shop_id`             VARCHAR(64)   NULL,
                    `price`               INT           NULL,
                    `currency`            VARCHAR(32)   NULL,
                    `metadata`            MEDIUMTEXT    NULL,
                    `coords_x`            FLOAT         NULL,
                    `coords_y`            FLOAT         NULL,
                    `coords_z`            FLOAT         NULL,
                    `note`                VARCHAR(255)  NULL,
                    `created_at`          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (`id`),
                    KEY `idx_action` (`action`),
                    KEY `idx_identifier` (`identifier`),
                    KEY `idx_created_at` (`created_at`),
                    KEY `idx_item_name` (`item_name`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
            ]]):format(tableName()))

            Utils.DebugPrint('Database table ready:', tableName())
        end)
    end
end

---Inserts a normalized log entry. Fully async (oxmysql), never blocks the
---caller. Silently returns if database storage isn't enabled/available.
---@param entry table
function Database.Log(entry)
    if not storageEnabled() or not MySQL then return end

    local player = entry.player or {}
    local target = entry.target
    local item = entry.item or {}
    local from = entry.from
    local to = entry.to
    local coords = entry.coords

    MySQL.insert(([[
        INSERT INTO `%s` (
            action, source, identifier, player_name, character_name, job_name, job_grade,
            target_source, target_identifier, target_name,
            item_name, item_label, amount,
            from_inventory_id, from_inventory_type, from_slot,
            to_inventory_id, to_inventory_type, to_slot,
            stash_id, vehicle_plate, shop_id, price, currency,
            metadata, coords_x, coords_y, coords_z, note
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]]):format(tableName()), {
        entry.action,
        player.source,
        player.identifier,
        player.name,
        player.charName,
        player.job,
        player.grade,
        target and target.source or nil,
        target and target.identifier or nil,
        target and (target.charName or target.name) or nil,
        item.name,
        item.label,
        item.amount,
        from and from.id and tostring(from.id) or nil,
        from and from.type or nil,
        from and from.slot or nil,
        to and to.id and tostring(to.id) or nil,
        to and to.type or nil,
        to and to.slot or nil,
        entry.stash,
        entry.vehicle,
        entry.shop and entry.shop.id or nil,
        entry.shop and entry.shop.price or nil,
        entry.shop and entry.shop.currency or nil,
        entry.metadataText,
        coords and coords.x or nil,
        coords and coords.y or nil,
        coords and coords.z or nil,
        entry.note,
    })
end

-- ------------------------------------------------------------
--  Retention cleanup
-- ------------------------------------------------------------

local function runCleanup()
    local days = Config.Database.retentionDays
    if not days or days <= 0 then return end

    local batchSize = Config.Database.cleanupBatchSize or 500

    local ok, affected = pcall(function()
        return MySQL.update.await(([[
            DELETE FROM `%s` WHERE `created_at` < (NOW() - INTERVAL ? DAY) LIMIT ?
        ]]):format(tableName()), { days, batchSize })
    end)

    if ok and affected and affected > 0 then
        Utils.DebugPrint(('Retention cleanup removed %d old log row(s).'):format(affected))
    end
end

if storageEnabled() then
    CreateThread(function()
        if not MySQL then return end

        local intervalMs = math.max(5, Config.Database.cleanupIntervalMinutes or 60) * 60000

        while true do
            Wait(intervalMs)
            if MySQL then runCleanup() end
        end
    end)
end
