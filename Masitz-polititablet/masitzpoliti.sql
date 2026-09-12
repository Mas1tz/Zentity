-- ============================================================
--  KC Polititablet — COMPLETE DATABASE RESET (polititablet_ prefix)
--  Kør hele filen som ÉN query i din ESX-database.
--  Den dropper både gamle mdt_* OG eventuelle polititablet_*
--  tabeller, og opretter alt frisk.
-- ============================================================

SET FOREIGN_KEY_CHECKS = 0;

-- ── DROP GAMLE mdt_* (fra v1/v2 prefix) ──────────────────────
DROP TABLE IF EXISTS `mdt_accounts`;
DROP TABLE IF EXISTS `mdt_duty_log`;
DROP TABLE IF EXISTS `mdt_citizens`;
DROP TABLE IF EXISTS `mdt_journals`;
DROP TABLE IF EXISTS `mdt_arrests`;
DROP TABLE IF EXISTS `mdt_warrants`;
DROP TABLE IF EXISTS `mdt_cases`;
DROP TABLE IF EXISTS `mdt_case_comments`;
DROP TABLE IF EXISTS `mdt_vehicle_records`;
DROP TABLE IF EXISTS `mdt_traffic_stops`;
DROP TABLE IF EXISTS `mdt_licenses`;
DROP TABLE IF EXISTS `mdt_charges`;
DROP TABLE IF EXISTS `mdt_dispatches`;
DROP TABLE IF EXISTS `mdt_patrol_units`;
DROP TABLE IF EXISTS `mdt_evidence`;
DROP TABLE IF EXISTS `mdt_laws`;
DROP TABLE IF EXISTS `mdt_audit_log`;

-- ── DROP polititablet_* (i tilfælde af genkørsel) ────────────
DROP TABLE IF EXISTS `polititablet_accounts`;
DROP TABLE IF EXISTS `polititablet_duty_log`;
DROP TABLE IF EXISTS `polititablet_citizens`;
DROP TABLE IF EXISTS `polititablet_journals`;
DROP TABLE IF EXISTS `polititablet_arrests`;
DROP TABLE IF EXISTS `polititablet_warrants`;
DROP TABLE IF EXISTS `polititablet_cases`;
DROP TABLE IF EXISTS `polititablet_case_comments`;
DROP TABLE IF EXISTS `polititablet_vehicle_records`;
DROP TABLE IF EXISTS `polititablet_traffic_stops`;
DROP TABLE IF EXISTS `polititablet_licenses`;
DROP TABLE IF EXISTS `polititablet_charges`;
DROP TABLE IF EXISTS `polititablet_dispatches`;
DROP TABLE IF EXISTS `polititablet_patrol_units`;
DROP TABLE IF EXISTS `polititablet_evidence`;
DROP TABLE IF EXISTS `polititablet_laws`;
DROP TABLE IF EXISTS `polititablet_audit_log`;

-- ── OPRET ALT FRISK ──────────────────────────────────────────
CREATE TABLE `polititablet_accounts` (
    `id`                  INT(11)      NOT NULL AUTO_INCREMENT,
    `identifier`          VARCHAR(60)  NOT NULL,
    `username`            VARCHAR(50)  NOT NULL,
    `password_hash`       VARCHAR(64)  NOT NULL,
    `password_salt`       VARCHAR(32)  NOT NULL,
    `must_change_pw`      TINYINT(1)   NOT NULL DEFAULT 1,
    `status`              ENUM('active','suspended','banned') NOT NULL DEFAULT 'active',
    `badge_number`        VARCHAR(20)  DEFAULT NULL,
    `rank`                VARCHAR(60)  DEFAULT 'Officer',
    `grade`               INT(3)       NOT NULL DEFAULT 0,
    `profile_image`       TEXT         DEFAULT NULL,
    `failed_attempts`     INT(3)       NOT NULL DEFAULT 0,
    `locked_until`        DATETIME     DEFAULT NULL,
    `created_by`          VARCHAR(60)  DEFAULT NULL,
    `created_by_name`     VARCHAR(100) DEFAULT NULL,
    `created_at`          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_login`          DATETIME     DEFAULT NULL,
    `last_login_ip`       VARCHAR(64)  DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_identifier` (`identifier`),
    UNIQUE KEY `uq_username`   (`username`),
    INDEX `idx_grade`  (`grade`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_duty_log` (
    `id`         INT(11)     NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(60) NOT NULL,
    `duty_on`    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `duty_off`   DATETIME    DEFAULT NULL,
    `seconds`    INT(11)     NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    INDEX `idx_ident`    (`identifier`),
    INDEX `idx_duty_on`  (`duty_on`),
    INDEX `idx_open`     (`identifier`, `duty_off`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_citizens` (
    `citizenid`   VARCHAR(60)  NOT NULL,
    `risk_level`  TINYINT(1)   NOT NULL DEFAULT 0,
    `mugshot_url` TEXT         DEFAULT NULL,
    `notes`       LONGTEXT     DEFAULT NULL,
    `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_journals` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,
    `citizenid`   VARCHAR(60)  NOT NULL,
    `author_id`   VARCHAR(60)  NOT NULL,
    `author_name` VARCHAR(100) NOT NULL,
    `title`       VARCHAR(255) NOT NULL,
    `body`        LONGTEXT     NOT NULL,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_cid`    (`citizenid`),
    INDEX `idx_author` (`author_id`),
    INDEX `idx_date`   (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_arrests` (
    `id`           INT(11)      NOT NULL AUTO_INCREMENT,
    `citizenid`    VARCHAR(60)  NOT NULL,
    `officer_id`   VARCHAR(60)  NOT NULL,
    `officer_name` VARCHAR(100) NOT NULL,
    `charges`      LONGTEXT     NOT NULL,
    `total_fine`   INT(11)      NOT NULL DEFAULT 0,
    `total_jail`   INT(11)      NOT NULL DEFAULT 0,
    `notes`        TEXT         DEFAULT NULL,
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_officer`   (`officer_id`),
    INDEX `idx_date`      (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_warrants` (
    `id`           INT(11)      NOT NULL AUTO_INCREMENT,
    `citizenid`    VARCHAR(60)  NOT NULL,
    `reason`       TEXT         NOT NULL,
    `risk_level`   TINYINT(1)   NOT NULL DEFAULT 1,
    `issued_by_id` VARCHAR(60)  NOT NULL,
    `issued_by`    VARCHAR(100) NOT NULL,
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at`   DATETIME     DEFAULT NULL,
    `active`       TINYINT(1)   NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_active`    (`active`),
    INDEX `idx_active_cid`(`active`, `citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_cases` (
    `id`            INT(11)      NOT NULL AUTO_INCREMENT,
    `case_number`   VARCHAR(20)  NOT NULL,
    `title`         VARCHAR(255) NOT NULL,
    `description`   LONGTEXT     DEFAULT NULL,
    `status`        ENUM('open','investigating','closed','archived') NOT NULL DEFAULT 'open',
    `priority`      TINYINT(1)   NOT NULL DEFAULT 1,
    `created_by_id` VARCHAR(60)  NOT NULL,
    `created_by`    VARCHAR(100) NOT NULL,
    `suspects`      LONGTEXT     DEFAULT NULL,
    `officers`      LONGTEXT     DEFAULT NULL,
    `evidence`      LONGTEXT     DEFAULT NULL,
    `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_case_number` (`case_number`),
    INDEX `idx_status`  (`status`),
    INDEX `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_case_comments` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,
    `case_id`     INT(11)      NOT NULL,
    `author_id`   VARCHAR(60)  NOT NULL,
    `author_name` VARCHAR(100) NOT NULL,
    `body`        LONGTEXT     NOT NULL,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_case` (`case_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_vehicle_records` (
    `plate`      VARCHAR(12)  NOT NULL,
    `stolen`     TINYINT(1)   NOT NULL DEFAULT 0,
    `seized`     TINYINT(1)   NOT NULL DEFAULT 0,
    `bolo`       TINYINT(1)   NOT NULL DEFAULT 0,
    `tracker`    TINYINT(1)   NOT NULL DEFAULT 0,
    `insurance`  TINYINT(1)   NOT NULL DEFAULT 1,
    `notes`      TEXT         DEFAULT NULL,
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_traffic_stops` (
    `id`           INT(11)      NOT NULL AUTO_INCREMENT,
    `plate`        VARCHAR(12)  NOT NULL,
    `officer_id`   VARCHAR(60)  NOT NULL,
    `officer_name` VARCHAR(100) NOT NULL,
    `notes`        TEXT         DEFAULT NULL,
    `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_plate` (`plate`),
    INDEX `idx_date`  (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_licenses` (
    `id`         INT(11)      NOT NULL AUTO_INCREMENT,
    `citizenid`  VARCHAR(60)  NOT NULL,
    `type`       VARCHAR(50)  NOT NULL,
    `status`     ENUM('valid','suspended','revoked') NOT NULL DEFAULT 'valid',
    `issued_by`  VARCHAR(100) DEFAULT NULL,
    `issued_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `expires_at` DATETIME     DEFAULT NULL,
    `notes`      TEXT         DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_cid_type` (`citizenid`, `type`),
    INDEX `idx_cid`  (`citizenid`),
    INDEX `idx_type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_charges` (
    `id`       INT(11)      NOT NULL AUTO_INCREMENT,
    `category` VARCHAR(100) NOT NULL,
    `label`    VARCHAR(255) NOT NULL,
    `fine`     INT(11)      NOT NULL DEFAULT 0,
    `jail`     INT(11)      NOT NULL DEFAULT 0,
    `law_ref`  VARCHAR(100) DEFAULT NULL,
    `active`   TINYINT(1)   NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    INDEX `idx_category` (`category`),
    INDEX `idx_active`   (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_dispatches` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,
    `code`        VARCHAR(20)  NOT NULL,
    `description` TEXT         NOT NULL,
    `location`    VARCHAR(255) DEFAULT NULL,
    `coords_x`    FLOAT        DEFAULT NULL,
    `coords_y`    FLOAT        DEFAULT NULL,
    `priority`    TINYINT(1)   NOT NULL DEFAULT 2,
    `status`      ENUM('active','assigned','resolved') NOT NULL DEFAULT 'active',
    `created_by_id` VARCHAR(60) DEFAULT NULL,
    `created_by`  VARCHAR(100) NOT NULL,
    `units`       TEXT         DEFAULT NULL,
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `resolved_at` DATETIME     DEFAULT NULL,
    `resolved_by` VARCHAR(100) DEFAULT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_status` (`status`),
    INDEX `idx_date`   (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_patrol_units` (
    `id`           INT(11)      NOT NULL AUTO_INCREMENT,
    `unit_call`    VARCHAR(30)  NOT NULL,
    `label`        VARCHAR(100) NOT NULL,
    `officer_id`   VARCHAR(60)  NOT NULL,
    `officer_name` VARCHAR(100) NOT NULL,
    `status`       TINYINT(1)   NOT NULL DEFAULT 1,
    `coords_x`     FLOAT        DEFAULT NULL,
    `coords_y`     FLOAT        DEFAULT NULL,
    `coords_z`     FLOAT        DEFAULT NULL,
    `last_update`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_officer` (`officer_id`),
    INDEX `idx_status`      (`status`),
    INDEX `idx_last_update` (`last_update`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_evidence` (
    `id`         INT(11)      NOT NULL AUTO_INCREMENT,
    `case_id`    INT(11)      DEFAULT NULL,
    `citizenid`  VARCHAR(60)  DEFAULT NULL,
    `type`       VARCHAR(50)  NOT NULL DEFAULT 'document',
    `label`      VARCHAR(255) NOT NULL,
    `value`      TEXT         DEFAULT NULL,
    `image_url`  TEXT         DEFAULT NULL,
    `added_by`   VARCHAR(100) NOT NULL,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_case`    (`case_id`),
    INDEX `idx_citizen` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_laws` (
    `id`        INT(11)      NOT NULL AUTO_INCREMENT,
    `book`      VARCHAR(100) NOT NULL,
    `paragraph` VARCHAR(20)  NOT NULL,
    `title`     VARCHAR(255) NOT NULL,
    `text`      LONGTEXT     NOT NULL,
    `active`    TINYINT(1)   NOT NULL DEFAULT 1,
    PRIMARY KEY (`id`),
    FULLTEXT KEY `ft_law` (`title`, `text`),
    INDEX `idx_book` (`book`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `polititablet_audit_log` (
    `id`         INT(11)      NOT NULL AUTO_INCREMENT,
    `actor_id`   VARCHAR(60)  NOT NULL,
    `actor_name` VARCHAR(100) NOT NULL,
    `action`     VARCHAR(100) NOT NULL,
    `target`     VARCHAR(255) DEFAULT NULL,
    `details`    TEXT         DEFAULT NULL,
    `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_actor`  (`actor_id`),
    INDEX `idx_action` (`action`),
    INDEX `idx_date`   (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ── DEFAULT BØDESKEMA ────────────────────────────────────────
INSERT INTO `polititablet_charges` (`category`,`label`,`fine`,`jail`,`law_ref`) VALUES
('Trafik','Hastighedsoverskridelse (under 20 km/t)',1500,0,'FVL §42'),
('Trafik','Hastighedsoverskridelse (over 20 km/t)',4500,0,'FVL §42'),
('Trafik','Kørsel mod rødt lys',2000,0,'FVL §54'),
('Trafik','Kørsel uden kørekort',5000,0,'FVL §56'),
('Trafik','Spirituskørsel (0.5-1.2 promille)',10000,2,'FVL §53'),
('Trafik','Spirituskørsel (over 1.2 promille)',25000,6,'FVL §53'),
('Trafik','Farlig kørsel',15000,4,'FVL §43'),
('Trafik','Stunt-kørsel',8000,0,'FVL §44'),
('Trafik','Vognbaneskift uden signal',1000,0,'FVL §38'),
('Våben','Ulovlig våbenbesiddelse',25000,15,'STK §192a'),
('Våben','Skydning på offentligt sted',50000,30,'STK §192'),
('Våben','Trusler med våben',30000,20,'STK §266'),
('Narkotika','Besiddelse af hash (under 50g)',3000,0,'LBK §191'),
('Narkotika','Besiddelse af hård narkotika',10000,6,'LBK §191'),
('Narkotika','Salg af narkotika',35000,24,'LBK §191 stk.2'),
('Vold','Simpel vold',5000,3,'STK §244'),
('Vold','Grov vold',20000,12,'STK §245'),
('Vold','Vold mod tjenestemand',40000,18,'STK §119'),
('Vold','Drabsforsøg',100000,60,'STK §237'),
('Tyveri','Butikstyveri',3000,0,'STK §276'),
('Tyveri','Indbrud',15000,8,'STK §276a');

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
--  FÆRDIG.
--  Verificér med:  DESCRIBE polititablet_warrants;
-- ============================================================


-- ============================================================
--  MIGRATION — MDT REWORK (nummerplade-tablet-rework)
-- ============================================================
--  Alt herunder er ADDITIVT og IKKE-destruktivt: den rører ikke
--  DROP TABLE'ene ovenfor, sletter ingen eksisterende data, og er
--  sikker at køre igen (hver kolonne/tabel tjekkes individuelt før
--  den tilføjes — samme mønster som MMgarage/Masitz-Anticheat).
--
--  Kør denne sektion (eller hele filen) ÉN gang på en eksisterende
--  installation for at opgradere uden at miste data. På en helt frisk
--  installation opretter blokken ovenfor allerede alt, og denne
--  sektion er da et no-op.
--
--  `polititablet_licenses` og `polititablet_charges`/`polititablet_laws`
--  RØRES IKKE: licenssystemet er fjernet fra UI/Lua (§8), men den
--  gamle tabel bevares urørt (undgår at destruere historisk data).
--  Bødeskema/Lovbog læses nu fra config.lua (Config.Fines/Config.Laws)
--  i stedet for `polititablet_charges`/`polititablet_laws` (§30) —
--  de to tabeller er derfor ikke længere i brug af resourcen, men
--  efterlades urørt af samme grund.
-- ============================================================

SET @dbname = DATABASE();

-- ── polititablet_warrants.image (§12 — billede på efterlysning) ──
SET @tbl = 'polititablet_warrants';
SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME=@tbl AND COLUMN_NAME='image');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `polititablet_warrants` ADD COLUMN `image` LONGTEXT DEFAULT NULL AFTER `risk_level`',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── polititablet_arrests — sigtelse-rework (§15-§19) ─────────────
SET @tbl = 'polititablet_arrests';

SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME=@tbl AND COLUMN_NAME='officers');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `polititablet_arrests` ADD COLUMN `officers` LONGTEXT DEFAULT NULL COMMENT ''JSON array: deltagende betjente'' AFTER `officer_name`',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME=@tbl AND COLUMN_NAME='images');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `polititablet_arrests` ADD COLUMN `images` LONGTEXT DEFAULT NULL COMMENT ''JSON array: klip/billeder (base64)''',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME=@tbl AND COLUMN_NAME='seized_items');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `polititablet_arrests` ADD COLUMN `seized_items` LONGTEXT DEFAULT NULL COMMENT ''JSON array: beslaglagte genstande''',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME=@tbl AND COLUMN_NAME='warrant_id');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `polititablet_arrests` ADD COLUMN `warrant_id` INT(11) DEFAULT NULL COMMENT ''sat hvis sigtelsen stammer fra en efterlysning (§13)''',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists = (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME=@tbl AND INDEX_NAME='idx_warrant');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `polititablet_arrests` ADD INDEX `idx_warrant` (`warrant_id`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── polititablet_patrol_units — flådestyring vehicle/seat (§22) ──
SET @tbl = 'polititablet_patrol_units';

SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME=@tbl AND COLUMN_NAME='vehicle_label');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `polititablet_patrol_units` ADD COLUMN `vehicle_label` VARCHAR(100) DEFAULT NULL',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME=@tbl AND COLUMN_NAME='vehicle_netid');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `polititablet_patrol_units` ADD COLUMN `vehicle_netid` INT(11) DEFAULT NULL',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists = (SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME=@tbl AND COLUMN_NAME='seat_role');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `polititablet_patrol_units` ADD COLUMN `seat_role` VARCHAR(10) DEFAULT NULL COMMENT ''driver | passenger''',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @exists = (SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME=@tbl AND INDEX_NAME='idx_vehicle_netid');
SET @ddl = IF(@exists = 0,
    'ALTER TABLE `polititablet_patrol_units` ADD INDEX `idx_vehicle_netid` (`vehicle_netid`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── polititablet_arrest_drafts — autosave/kladde (§21) ───────────
-- Én kladde pr. (betjent, borger). Overskrives (ON DUPLICATE KEY) ved
-- hvert autosave i stedet for at vokse ubegrænset. Fjernes når
-- sigtelsen oprettes, eller når betjenten aktivt sletter kladden.
CREATE TABLE IF NOT EXISTS `polititablet_arrest_drafts` (
    `id`         INT(11)      NOT NULL AUTO_INCREMENT,
    `officer_id` VARCHAR(60)  NOT NULL,
    `citizenid`  VARCHAR(60)  NOT NULL,
    `payload`    LONGTEXT     NOT NULL,
    `updated_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_officer_citizen` (`officer_id`, `citizenid`),
    INDEX `idx_officer` (`officer_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
--  MIGRATION FÆRDIG.
--  Verificér med:  DESCRIBE polititablet_arrests;
--                  DESCRIBE polititablet_patrol_units;
--                  SHOW TABLES LIKE 'polititablet_arrest_drafts';
-- ============================================================
