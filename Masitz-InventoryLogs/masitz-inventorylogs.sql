-- Masitz-InventoryLogs
-- Optional manual import. server/database.lua already creates this table
-- automatically (CREATE TABLE IF NOT EXISTS) on startup when
-- Config.Storage is 'database' or 'both', so running this file by hand is
-- only useful if you want the table to exist before first boot, or you
-- prefer to manage schema migrations yourself.

CREATE TABLE IF NOT EXISTS `masitz_inventory_logs` (
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
