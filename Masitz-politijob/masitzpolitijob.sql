-- ============================================================
-- MM-PolitiJob v3.0 – masitzpolitijob.sql
-- Kør denne fil i din database (f.eks. via HeidiSQL eller phpMyAdmin)
-- ============================================================

CREATE TABLE IF NOT EXISTS `police_activity` (
    `identifier`   VARCHAR(64)  NOT NULL,
    `char_name`    VARCHAR(100) DEFAULT 'Ukendt',
    `last_clockin` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    `total_time`   INT          DEFAULT 0,
    `weekly_time`  INT          DEFAULT 0,
    `monthly_time` INT          DEFAULT 0,
    `last_update`  DATE         DEFAULT (CURRENT_DATE),
    PRIMARY KEY (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================
-- Elevfeedback (v3.1 rework)
-- ============================================================
CREATE TABLE IF NOT EXISTS `police_feedback` (
    `id`                 INT          NOT NULL AUTO_INCREMENT,
    `target_identifier`  VARCHAR(64)  NOT NULL,
    `target_name`        VARCHAR(100) DEFAULT 'Ukendt',
    `author_identifier`  VARCHAR(64)  NOT NULL,
    `author_name`        VARCHAR(100) DEFAULT 'Ukendt',
    `feedback`           TEXT         NOT NULL,
    `ratings`            TEXT         DEFAULT NULL,
    `created_at`         TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `target_identifier` (`target_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
