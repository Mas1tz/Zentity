-- ============================================================================
--  Masitz-Anticheat.sql
--  Kør én gang. Sikker at køre flere gange (CREATE TABLE IF NOT EXISTS).
--
--  Dette script opretter KUN Masitz-Anticheat's egne tabeller. Det rører
--  IKKE `owned_vehicles` eller andre eksisterende MM-garage-tabeller -
--  anti-nummerplade bruger `owned_vehicles` (plate = PRIMARY KEY,
--  owner = INDEX) som den findes i MMgarage.sql, uændret.
-- ============================================================================

-- ── PERMANENTE BANS ──────────────────────────────────────────────────────
-- Overlever resource-restart, server-restart og reconnect (ren DB-state).
CREATE TABLE IF NOT EXISTS `masitz_anticheat_bans` (
    `id`                  INT(11)       NOT NULL AUTO_INCREMENT,

    `player_name`         VARCHAR(100)  DEFAULT NULL,

    `identifier_license`  VARCHAR(100)  DEFAULT NULL,
    `identifier_license2` VARCHAR(100)  DEFAULT NULL,
    `identifier_discord`  VARCHAR(100)  DEFAULT NULL,
    `identifier_steam`    VARCHAR(100)  DEFAULT NULL,
    `identifier_fivem`    VARCHAR(100)  DEFAULT NULL,
    `identifier_xbl`      VARCHAR(100)  DEFAULT NULL,
    `identifier_live`     VARCHAR(100)  DEFAULT NULL,
    `identifier_ip`       VARCHAR(64)   DEFAULT NULL,

    `module`              VARCHAR(50)   NOT NULL DEFAULT 'anti-nummerplade',
    `detection_type`      VARCHAR(60)   DEFAULT NULL,
    `confidence_level`    TINYINT(1)    NOT NULL DEFAULT 0,
    `reason`              TEXT          DEFAULT NULL,
    `evidence`            JSON          DEFAULT NULL,

    `banned_at`           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `banned_by`           VARCHAR(50)   NOT NULL DEFAULT 'SYSTEM',
    `active`              TINYINT(1)    NOT NULL DEFAULT 1,

    PRIMARY KEY (`id`),
    INDEX `idx_license`   (`identifier_license`),
    INDEX `idx_license2`  (`identifier_license2`),
    INDEX `idx_discord`   (`identifier_discord`),
    INDEX `idx_steam`     (`identifier_steam`),
    INDEX `idx_ip`        (`identifier_ip`),
    INDEX `idx_active`    (`active`),
    INDEX `idx_module`    (`module`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── SECURITY EVENT LOG ───────────────────────────────────────────────────
-- Kun LEVEL >= 2 (suspicious/strong/confirmed/critical) skrives hertil -
-- LEVEL 0/1 (normal / malformed request) logges kun i konsollen, for at
-- undgå unødvendigt voksende data (se spec punkt 40).
CREATE TABLE IF NOT EXISTS `masitz_anticheat_security_events` (
    `id`                      INT(11)      NOT NULL AUTO_INCREMENT,
    `event_time`              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    `level`                   TINYINT(1)   NOT NULL DEFAULT 0,
    `detection_type`          VARCHAR(60)  DEFAULT NULL,

    `plate_old`               VARCHAR(12)  DEFAULT NULL,
    `plate_new`                VARCHAR(12)  DEFAULT NULL,
    `vehicle_owner`           VARCHAR(60)  DEFAULT NULL,

    `responsible_identifier`  VARCHAR(100) DEFAULT NULL,
    `responsible_name`        VARCHAR(100) DEFAULT NULL,
    `source_id`               VARCHAR(10)  DEFAULT NULL,
    `duplicate_owner`         VARCHAR(60)  DEFAULT NULL,

    `action_taken`            VARCHAR(30)  DEFAULT NULL,
    `details`                 JSON         DEFAULT NULL,

    PRIMARY KEY (`id`),
    INDEX `idx_level`        (`level`),
    INDEX `idx_responsible`  (`responsible_identifier`),
    INDEX `idx_plate_old`    (`plate_old`),
    INDEX `idx_plate_new`    (`plate_new`),
    INDEX `idx_event_time`   (`event_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
