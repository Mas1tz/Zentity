-- ============================================================
--  Masitz-garage | sql/masitz_garage.sql
--  Sikker, gentagelig migration — kør én gang (eller flere, det
--  gør ingen forskel). ALDRIG DROP TABLE, ALDRIG DELETE af
--  eksisterende køretøjer/nøgler/impound-data.
--
--  Denne fil er 100% identisk med den oprindelige MMgarage.sql,
--  MED TILFØJELSE af én ny kolonne (vehicle_name, §5) nederst —
--  alt eksisterende data i owned_vehicles/vehicle_keys/impound_log
--  er upåvirket.
-- ============================================================

-- ── OWNED VEHICLES (opretter kun hvis tabellen slet ikke findes) ──
CREATE TABLE IF NOT EXISTS `owned_vehicles` (
    `owner`            VARCHAR(60)   NOT NULL,
    `plate`            VARCHAR(12)   NOT NULL,
    `vehicle`          LONGTEXT      DEFAULT NULL,

    `stored`           TINYINT(1)    NOT NULL DEFAULT 1,
    `parking`          VARCHAR(60)   DEFAULT 'midtby',
    `last_garage`      VARCHAR(60)   DEFAULT 'midtby',
    `garage_type`      VARCHAR(20)   NOT NULL DEFAULT 'car'
                           COMMENT 'car | boat | plane',

    `impound`          TINYINT(1)    NOT NULL DEFAULT 0,
    `impound_location` VARCHAR(60)   DEFAULT NULL,
    `impound_reason`   VARCHAR(255)  DEFAULT NULL,
    `impound_fee`      INT(11)       NOT NULL DEFAULT 0,
    `impound_at`       DATETIME      DEFAULT NULL,

    `fuel`             FLOAT         NOT NULL DEFAULT 100.0,
    `engine_health`    FLOAT         NOT NULL DEFAULT 1000.0,
    `body_health`      FLOAT         NOT NULL DEFAULT 1000.0,

    PRIMARY KEY (`plate`),
    INDEX `idx_owner`        (`owner`),
    INDEX `idx_stored`       (`stored`),
    INDEX `idx_parking`      (`parking`),
    INDEX `idx_impound`      (`impound`),
    INDEX `idx_garage_type`  (`garage_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── VEHICLE KEYS (persistency) ───────────────────────────────
CREATE TABLE IF NOT EXISTS `vehicle_keys` (
    `id`         INT(11)      NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60)  NOT NULL,
    `plate`      VARCHAR(12)  NOT NULL,
    `given_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_key`    (`identifier`, `plate`),
    INDEX      `idx_ident` (`identifier`),
    INDEX      `idx_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── IMPOUND LOG ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `impound_log` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,
    `plate`       VARCHAR(12)  NOT NULL,
    `owner`       VARCHAR(60)  NOT NULL,
    `location`    VARCHAR(60)  DEFAULT NULL,
    `reason`      VARCHAR(255) DEFAULT NULL,
    `fee`         INT(11)      NOT NULL DEFAULT 0,
    `paid`        TINYINT(1)   NOT NULL DEFAULT 0,
    `impound_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `released_at` DATETIME     DEFAULT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_plate` (`plate`),
    INDEX `idx_owner` (`owner`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- MIGRATION (eksisterende installation af owned_vehicles)
-- Hver kolonne tjekkes og tilføjes individuelt, uden AFTER-afhængighed
-- til andre kolonner. Sikker at køre flere gange.
-- ============================================================

SET @dbname   = DATABASE();
SET @tblname  = 'owned_vehicles';

-- ---- stored ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'stored');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `stored` TINYINT(1) NOT NULL DEFAULT 1',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- parking ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'parking');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `parking` VARCHAR(60) DEFAULT ''midtby''',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- last_garage ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'last_garage');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `last_garage` VARCHAR(60) DEFAULT ''midtby''',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- garage_type ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'garage_type');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `garage_type` VARCHAR(20) NOT NULL DEFAULT ''car'' COMMENT ''car | boat | plane''',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- impound ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'impound');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `impound` TINYINT(1) NOT NULL DEFAULT 0',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- impound_location ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'impound_location');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `impound_location` VARCHAR(60) DEFAULT NULL',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- impound_reason ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'impound_reason');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `impound_reason` VARCHAR(255) DEFAULT NULL',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- impound_fee ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'impound_fee');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `impound_fee` INT(11) NOT NULL DEFAULT 0',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- impound_at ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'impound_at');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `impound_at` DATETIME DEFAULT NULL',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- fuel ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'fuel');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `fuel` FLOAT NOT NULL DEFAULT 100.0',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- engine_health ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'engine_health');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `engine_health` FLOAT NOT NULL DEFAULT 1000.0',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- body_health ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'body_health');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `body_health` FLOAT NOT NULL DEFAULT 1000.0',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- vehicle_name (§5 — NYT i Masitz-garage) ----
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND COLUMN_NAME = 'vehicle_name');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD COLUMN `vehicle_name` VARCHAR(40) DEFAULT NULL',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ============================================================
-- INDEXES (tilføjes individuelt, kun hvis kolonnen findes OG
-- indexet ikke allerede findes)
-- ============================================================

-- ---- idx_owner ----
SET @exists = (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND INDEX_NAME = 'idx_owner');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD INDEX `idx_owner` (`owner`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- idx_stored ----
SET @exists = (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND INDEX_NAME = 'idx_stored');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD INDEX `idx_stored` (`stored`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- idx_parking ----
SET @exists = (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND INDEX_NAME = 'idx_parking');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD INDEX `idx_parking` (`parking`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- idx_impound ----
SET @exists = (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND INDEX_NAME = 'idx_impound');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD INDEX `idx_impound` (`impound`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ---- idx_garage_type ----
SET @exists = (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tblname AND INDEX_NAME = 'idx_garage_type');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `owned_vehicles` ADD INDEX `idx_garage_type` (`garage_type`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
