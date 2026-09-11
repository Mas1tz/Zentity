-- ============================================================
--  Masitz-AgriHub | sql/install.sql
--  Kør én gang. Sikkert at genkøre (CREATE TABLE IF NOT EXISTS).
--  Ingen DROP TABLE, ingen DELETE af eksisterende data.
-- ============================================================

-- ── ACCESS CONTROL ──────────────────────────────────────────
-- Hvem har adgang til AgriHub. SUPER_ADMIN (Config.Agri.Admin.discordId)
-- kræver INGEN række her — den afgøres udelukkende server-side ud fra
-- Discord ID ved hvert login/admin-kald (se server/access.lua).
CREATE TABLE IF NOT EXISTS `agrihub_users` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,
    `identifier`  VARCHAR(60)  NOT NULL,
    `discord_id`  VARCHAR(30)  DEFAULT NULL,
    `player_name` VARCHAR(100) DEFAULT NULL,
    `granted_by`  VARCHAR(60)  DEFAULT NULL,
    `granted_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `revoked_at`  DATETIME     DEFAULT NULL,
    `status`      VARCHAR(10)  NOT NULL DEFAULT 'active' COMMENT 'active | revoked',
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_identifier` (`identifier`),
    INDEX `idx_discord`  (`discord_id`),
    INDEX `idx_status`   (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── KONTRAKTER (dækker BÅDE NPC- og spiller-udlejning) ──────
-- NPC-udlejning: owner_identifier = NULL, owner_approved/owner_signed
-- sættes automatisk ved oprettelse (se server/rental.lua).
CREATE TABLE IF NOT EXISTS `agrihub_contracts` (
    `id`                INT(11)      NOT NULL AUTO_INCREMENT,
    `contract_id`       VARCHAR(20)  NOT NULL COMMENT 'AGR-000184',
    `owner_identifier`  VARCHAR(60)  DEFAULT NULL COMMENT 'NULL = AgriHub/NPC',
    `renter_identifier` VARCHAR(60)  NOT NULL,
    `vehicle_model`     VARCHAR(50)  NOT NULL,
    `vehicle_plate`     VARCHAR(12)  DEFAULT NULL,
    `deposit`           INT(11)      NOT NULL DEFAULT 0,
    `rent`              INT(11)      NOT NULL DEFAULT 0,
    `payment_method`    VARCHAR(10)  NOT NULL DEFAULT 'bank' COMMENT 'bank | money',
    `start_at`          DATETIME     DEFAULT NULL,
    `expires_at`        DATETIME     DEFAULT NULL,
    `status`            VARCHAR(20)  NOT NULL DEFAULT 'pending'
                             COMMENT 'pending | active | completed | expired | cancelled',
    `owner_approved`    TINYINT(1)   NOT NULL DEFAULT 0,
    `renter_approved`   TINYINT(1)   NOT NULL DEFAULT 0,
    `owner_signed`      TINYINT(1)   NOT NULL DEFAULT 0,
    `renter_signed`     TINYINT(1)   NOT NULL DEFAULT 0,
    `deposit_refunded`  TINYINT(1)   NOT NULL DEFAULT 0,
    `created_at`        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_contract_id` (`contract_id`),
    INDEX `idx_owner`   (`owner_identifier`),
    INDEX `idx_renter`  (`renter_identifier`),
    INDEX `idx_status`  (`status`),
    INDEX `idx_expires` (`expires_at`),
    INDEX `idx_plate`   (`vehicle_plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── TASKS (diesel/levering/redskab/dyr/maskine-til-NPC) ─────
-- Aktiv + historik i ÉN tabel via `status` — ingen data mistes,
-- ingen ekstra CPU-tung flytte-mellem-tabeller-logik nødvendig.
CREATE TABLE IF NOT EXISTS `agrihub_tasks` (
    `id`                 INT(11)      NOT NULL AUTO_INCREMENT,
    `task_id`            VARCHAR(20)  NOT NULL COMMENT 'AGR-12345',
    `type`               VARCHAR(30)  NOT NULL
                              COMMENT 'diesel | fertilizer_delivery | pesticide_delivery | equipment_delivery | animal_transport | machinery_npc',
    `player_identifier`  VARCHAR(60)  DEFAULT NULL COMMENT 'NULL = ikke claimet endnu',
    `data`               LONGTEXT     NOT NULL COMMENT 'JSON: destinationer, vehicle, trailer, cargo, dyretype, stop-progress',
    `reward`             INT(11)      NOT NULL DEFAULT 0,
    `status`             VARCHAR(20)  NOT NULL DEFAULT 'available'
                              COMMENT 'available | active | completed | expired | cancelled',
    `created_at`         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `claimed_at`         DATETIME     DEFAULT NULL,
    `completed_at`       DATETIME     DEFAULT NULL,
    `expires_at`         DATETIME     DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_task_id` (`task_id`),
    INDEX `idx_type`   (`type`),
    INDEX `idx_player` (`player_identifier`),
    INDEX `idx_status` (`status`),
    INDEX `idx_expires`(`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── AUDIT LOG (DB-side, i tillæg til Discord webhooks) ───────
CREATE TABLE IF NOT EXISTS `agrihub_logs` (
    `id`          INT(11)      NOT NULL AUTO_INCREMENT,
    `action`      VARCHAR(50)  NOT NULL,
    `identifier`  VARCHAR(60)  DEFAULT NULL,
    `discord_id`  VARCHAR(30)  DEFAULT NULL,
    `player_name` VARCHAR(100) DEFAULT NULL,
    `data`        LONGTEXT     DEFAULT NULL COMMENT 'JSON — kontekstuelle detaljer',
    `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_action`     (`action`),
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_created`    (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
