-- ══════════════════════════════════════════════════════════
--  mm-christmas — Database Install (fresh installs)
--
--  Already have an older mm-christmas/MM-christmasevent installed?
--  You do NOT need to run this file again and you will NOT lose any
--  data. server/database.lua automatically checks for and adds any
--  missing columns (claimed_rewards, world_gifts_found) the first
--  time the resource starts, using ALTER TABLE ADD COLUMN - it never
--  drops or rewrites existing rows. This file only matters for a
--  brand new installation that has no `mm_christmas_players` table
--  at all yet.
-- ══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS `mm_christmas_players` (
    `identifier`        VARCHAR(60)  NOT NULL,
    `name`              VARCHAR(60)  NOT NULL DEFAULT '',
    `xp`                INT          NOT NULL DEFAULT 0,
    `level`             INT          NOT NULL DEFAULT 1,
    `coins`             INT          NOT NULL DEFAULT 0,
    `trees_decorated`   INT          NOT NULL DEFAULT 0,
    `snowmen_built`     INT          NOT NULL DEFAULT 0,
    `gifts_found`       INT          NOT NULL DEFAULT 0,
    `personal_gifts`    INT          NOT NULL DEFAULT 0,
    `distance_driven`   FLOAT        NOT NULL DEFAULT 0,
    `distance_run`      FLOAT        NOT NULL DEFAULT 0,
    `daily_tasks`       LONGTEXT     NULL,
    `weekly_tasks`      LONGTEXT     NULL,
    `daily_reset`       DATE         NULL,
    `weekly_reset`      DATE         NULL,
    `trees_done`        LONGTEXT     NULL,
    `shop_purchases`    LONGTEXT     NULL,
    `claimed_rewards`   LONGTEXT     NULL,
    `world_gifts_found` LONGTEXT     NULL,
    `created_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`),
    -- Speeds up the leaderboard's ORDER BY level DESC, xp DESC and the
    -- individual per-category sorts done in server/main.lua.
    INDEX `idx_level_xp` (`level` DESC, `xp` DESC),
    INDEX `idx_trees`    (`trees_decorated` DESC),
    INDEX `idx_snowmen`  (`snowmen_built` DESC),
    INDEX `idx_gifts`    (`gifts_found` DESC),
    INDEX `idx_coins`    (`coins` DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ══════════════════════════════════════════════════════════
--  LEADERBOARD VIEW (kept for any external tooling/dashboards that
--  may want a simple read-only view; the resource itself queries
--  the table directly for the live in-game leaderboard).
-- ══════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW `mm_christmas_leaderboard` AS
SELECT
    `identifier`,
    `name`,
    `level`,
    `xp`,
    `trees_decorated`,
    `snowmen_built`,
    `gifts_found`,
    `coins`
FROM `mm_christmas_players`
ORDER BY `level` DESC, `xp` DESC;
