-- ============================================================
--  mm-faktura – SQL Installation (V2)
--  Kør i din database
-- ============================================================

CREATE TABLE IF NOT EXISTS `mm_faktura_invoices` (
    `id`                INT             AUTO_INCREMENT,
    `target_identifier` VARCHAR(60)     NOT NULL,
    `target_name`       VARCHAR(50)     DEFAULT NULL,
    `from_identifier`   VARCHAR(60)     DEFAULT NULL,
    `from_name`         VARCHAR(50)     DEFAULT NULL,
    `job`               VARCHAR(50)     DEFAULT NULL,
    `category_label`    VARCHAR(255)    DEFAULT NULL,
    `meta`              LONGTEXT,
    `amount`            INT             NOT NULL DEFAULT 0,
    `paid`              TINYINT(1)      NOT NULL DEFAULT 0,
    `paid_at`           TIMESTAMP       NULL DEFAULT NULL,
    `created_at`        TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_target` (`target_identifier`),
    INDEX `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Kategorier/varer oprettet direkte i tabletten (lægges oveni Config.Categories
-- fra config.lua – redigerer IKKE i config-filens grund-kategorier).
CREATE TABLE IF NOT EXISTS `mm_faktura_custom_categories` (
    `id`           INT             AUTO_INCREMENT,
    `job`          VARCHAR(50)     NOT NULL,
    `group_name`   VARCHAR(100)    NOT NULL,
    `cat_id`       VARCHAR(60)     NOT NULL,
    `label`        VARCHAR(255)    NOT NULL,
    `price`        INT             NOT NULL DEFAULT 0,
    `created_by`   VARCHAR(60)     DEFAULT NULL,
    `created_at`   TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_job_cat` (`job`, `cat_id`),
    INDEX `idx_job` (`job`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
