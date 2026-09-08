--[[
    Database-laget for V2. Opretter tabellerne automatisk ved resource-start
    (sikkerhedsnet oveni sql/install.sql), og eksponerer DatabaseReady, så
    andre server-moduler (task-engine, trust factor osv.) trygt kan vente
    med at røre databasen til forbindelsen rent faktisk er klar.
]]

DatabaseReady = false

-- Skal være 100% identisk med sql/install.sql, så de to aldrig kan drifte
-- fra hinanden over tid.
local TABLE_DEFINITIONS = {
    [[
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
        `total_removed_manual`           INT UNSIGNED NOT NULL DEFAULT 0,
        `trust_factor`                   DECIMAL(5,2) NOT NULL DEFAULT 100.00,
        `active_minutes_since_recovery`  INT UNSIGNED NOT NULL DEFAULT 0,
        `escape_pause_until`             BIGINT UNSIGNED NOT NULL DEFAULT 0,
        `steam_avatar_updated_at`        DATETIME NULL DEFAULT NULL,
        `created_at`                     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `updated_at`                     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `uq_sf_players_identifier` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `sf_history` (
        `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `identifier`   VARCHAR(64)  NOT NULL,
        `amount`       INT          NOT NULL,
        `reason`       VARCHAR(255) NOT NULL,
        `actor_name`   VARCHAR(100) DEFAULT NULL,
        `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_sf_history_identifier` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `sf_auditlog` (
        `id`                 INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `action`             VARCHAR(50)  NOT NULL,
        `actor_identifier`   VARCHAR(64)  DEFAULT NULL,
        `actor_name`         VARCHAR(100) DEFAULT NULL,
        `target_identifier`  VARCHAR(64)  DEFAULT NULL,
        `target_name`        VARCHAR(100) DEFAULT NULL,
        `details`            TEXT         DEFAULT NULL,
        `created_at`         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `idx_sf_auditlog_action` (`action`),
        KEY `idx_sf_auditlog_target` (`target_identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `sf_settings` (
        `setting_key`    VARCHAR(64) NOT NULL,
        `setting_value`  TEXT        NOT NULL,
        `updated_at`     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (`setting_key`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
}

-- Kolonner tilføjet EFTER første release. CREATE TABLE IF NOT EXISTS
-- rører ikke en tabel der allerede findes, så eksisterende installationer
-- skal migreres eksplicit her. Wrappet i pcall, fordi "ADD COLUMN IF NOT
-- EXISTS" ikke findes på alle MySQL/MariaDB-versioner — fejler den, har
-- kolonnen højst sandsynligt eksisteret i forvejen.
local MIGRATIONS = {
    "ALTER TABLE `sf_players` ADD COLUMN IF NOT EXISTS `total_removed_manual` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `total_completed`;",
    "ALTER TABLE `sf_players` ADD COLUMN IF NOT EXISTS `steam_avatar_updated_at` DATETIME NULL DEFAULT NULL AFTER `escape_pause_until`;",
}

local function EnsureTables()
    for _, definition in ipairs(TABLE_DEFINITIONS) do
        exports.oxmysql:executeSync(definition, {})
    end

    for _, migration in ipairs(MIGRATIONS) do
        pcall(function()
            exports.oxmysql:executeSync(migration, {})
        end)
    end
end

-- ------------------------------------------------------------
-- AUDIT LOG — skriv-funktion, tilgængelig for alle andre server-moduler.
-- Ligger her (ikke i et separat "audit.lua") fordi den er en ren
-- databaseoperation uden egen forretningslogik.
-- ------------------------------------------------------------
function InsertAuditLog(action, actorIdentifier, actorName, targetIdentifier, targetName, details)
    if not DatabaseReady then return end

    exports.oxmysql:insert(
        'INSERT INTO sf_auditlog (action, actor_identifier, actor_name, target_identifier, target_name, details) VALUES (?, ?, ?, ?, ?, ?)',
        {
            action,
            actorIdentifier,
            actorName,
            targetIdentifier,
            targetName,
            Utils.SafeJsonEncode(details or {}),
        }
    )
end

-- ------------------------------------------------------------
-- HISTORY LOG — spillerens egen, synlige opgavehistorik.
-- ------------------------------------------------------------
function InsertHistory(identifier, amount, reason, actorName)
    if not DatabaseReady then return end

    exports.oxmysql:insert(
        'INSERT INTO sf_history (identifier, amount, reason, actor_name) VALUES (?, ?, ?, ?)',
        { identifier, amount, reason, actorName }
    )
end

-- ------------------------------------------------------------
-- STARTUP
-- ------------------------------------------------------------
local function OnDatabaseReady()
    EnsureTables()
    DatabaseReady = true
    TriggerEvent('mm_sf:database:ready')
    print('^2[Masitz-samfundstjeneste]^7 Database klar (tabeller verificeret)')
end

CreateThread(function()
    -- Vent til selve oxmysql-resourcen er startet, uanset hvilken
    -- rækkefølge resources loader i.
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(100)
    end

    -- Nyere oxmysql-versioner har et 'ready'-export, som garanterer at
    -- selve databaseforbindelsen (ikke bare resourcen) er etableret.
    -- Ældre versioner har det ikke, og et kald på et ikke-eksisterende
    -- export fejler med det samme, hvilket er præcis den fejl du så.
    -- Vi forsøger derfor 'ready' først, og falder sikkert tilbage til
    -- en kort ventetid hvis exportet ikke findes.
    local usedReadyExport = pcall(function()
        exports.oxmysql:ready(OnDatabaseReady)
    end)

    if not usedReadyExport then
        print('^3[Masitz-samfundstjeneste]^7 oxmysql har intet \'ready\'-export (ældre version) — falder tilbage til kort ventetid')
        Wait(1000)
        OnDatabaseReady()
    end
end)
