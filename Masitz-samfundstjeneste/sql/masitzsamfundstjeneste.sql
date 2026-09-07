-- ═══════════════════════════════════════════════════════════
--  MM SAMFUNDSTJENESTE V2 — DATABASESKEMA
--  Kør denne fil én gang ved installation. server/database.lua
--  opretter desuden automatisk de samme tabeller ved resource-start,
--  hvis de ikke allerede findes — så denne fil er ikke strengt
--  påkrævet, men anbefalet for et rent, forudsigeligt setup.
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS `sf_players` (
    `id`                             INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier`                     VARCHAR(64)  NOT NULL,
    `name`                           VARCHAR(100) NOT NULL DEFAULT 'Ukendt',

    `discord_id`                     VARCHAR(32)  DEFAULT NULL,
    `discord_name`                   VARCHAR(100) DEFAULT NULL,
    `discord_avatar`                 VARCHAR(255) DEFAULT NULL,

    `steam_id`                       VARCHAR(32)  DEFAULT NULL,
    `steam_name`                     VARCHAR(100) DEFAULT NULL,
    `steam_avatar`                   VARCHAR(255) DEFAULT NULL,

    `active_tasks`                   INT UNSIGNED NOT NULL DEFAULT 0,
    `total_assigned`                 INT UNSIGNED NOT NULL DEFAULT 0,
    `total_completed`                INT UNSIGNED NOT NULL DEFAULT 0,
    -- Antal opgaver fjernet manuelt af Staff/Owner (remove/set nedad/release).
    -- Tæller IKKE gennemførte opgaver eller automatisk tidsreduktion.
    `total_removed_manual`           INT UNSIGNED NOT NULL DEFAULT 0,

    `trust_factor`                   DECIMAL(5,2) NOT NULL DEFAULT 100.00,
    -- Antal reelt aktive minutter akkumuleret siden sidste recovery-tick.
    -- Nulstilles hver gang der udbetales trust factor-recovery.
    `active_minutes_since_recovery`  INT UNSIGNED NOT NULL DEFAULT 0,

    -- Unix-millisekund-timestamp indtil hvilket automatisk tidsreduktion er
    -- sat på pause pga. et flugtforsøg. 0 = ingen aktiv pause.
    `escape_pause_until`             BIGINT UNSIGNED NOT NULL DEFAULT 0,

    -- Hvornår Steam-avatar/navn sidst blev opdateret fra Steam Web API.
    `steam_avatar_updated_at`        DATETIME NULL DEFAULT NULL,

    `created_at`                     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`                     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_sf_players_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Spillerens EGEN opgavehistorik (vises på deres eget dashboard).
CREATE TABLE IF NOT EXISTS `sf_history` (
    `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `identifier`   VARCHAR(64)  NOT NULL,
    -- Signeret: +50, -1, -25 osv.
    `amount`       INT          NOT NULL,
    `reason`       VARCHAR(255) NOT NULL,
    -- Fx "Staff", "System", eller et konkret navn. NULL hvis ikke relevant.
    `actor_name`   VARCHAR(100) DEFAULT NULL,
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    KEY `idx_sf_history_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Komplet audit-log over ALLE staff/owner-handlinger. Kun Owner må se denne
-- i UI'en, i modsætning til sf_history som spilleren selv må se sin egen del af.
CREATE TABLE IF NOT EXISTS `sf_auditlog` (
    `id`                 INT UNSIGNED NOT NULL AUTO_INCREMENT,
    -- fx: give_service, add_tasks, remove_tasks, set_tasks, release,
    -- modify_trust, change_config, auto_complete, auto_reduction,
    -- escape, trust_recovery
    `action`             VARCHAR(50)  NOT NULL,

    `actor_identifier`   VARCHAR(64)  DEFAULT NULL,
    `actor_name`         VARCHAR(100) DEFAULT NULL,

    `target_identifier`  VARCHAR(64)  DEFAULT NULL,
    `target_name`        VARCHAR(100) DEFAULT NULL,

    -- JSON-encoded ekstra detaljer, fx {"amount": 25, "reason": "Ny dom"}
    `details`            TEXT         DEFAULT NULL,

    `created_at`         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    KEY `idx_sf_auditlog_action` (`action`),
    KEY `idx_sf_auditlog_target` (`target_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Owner-konfigurerbare runtime-indstillinger (trust factor mode, time
-- reduction interval osv.), så Owner kan ændre dem live fra UI'en uden at
-- skulle redigere config.lua og genstarte resourcen. Værdier gemmes som JSON.
CREATE TABLE IF NOT EXISTS `sf_settings` (
    `setting_key`    VARCHAR(64) NOT NULL,
    `setting_value`  TEXT        NOT NULL,
    `updated_at`     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
