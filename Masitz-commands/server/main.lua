-- ============================================================
--  Masitz-commands | server/main.lua
--
--  Bootstrap: databasetabeller, forbindelses-ban-håndhævelse, og de
--  fælles hjælpefunktioner (identifiers, permissions, cooldown,
--  target-validering) som pov.lua/check.lua bygger ovenpå. Ligger
--  samlet ét sted, ligesom mm-adminpakke/server/security.lua, så
--  pov.lua og check.lua aldrig laver deres eget parallelle tjek.
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

DatabaseReady = false

Helpers = {}

local function DebugPrint(fmt, ...)
    if not Config.Debug then return end
    print(('[Masitz-commands] ' .. fmt):format(...))
end
Helpers.DebugPrint = DebugPrint

-- ------------------------------------------------------------------
--  DATABASE
-- ------------------------------------------------------------------
local TABLE_DEFINITIONS = {
    [[
    CREATE TABLE IF NOT EXISTS `masitz_commands_pov_history` (
        `identifier`   VARCHAR(64) NOT NULL,
        `fail_count`   INT UNSIGNED NOT NULL DEFAULT 0,
        `last_fail_at` DATETIME NULL DEFAULT NULL,
        `banned`       TINYINT(1) NOT NULL DEFAULT 0,
        `banned_at`    DATETIME NULL DEFAULT NULL,
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `masitz_commands_pov_requests` (
        `request_id`              VARCHAR(32) NOT NULL,
        `target_identifier`       VARCHAR(64) NOT NULL,
        `target_name`             VARCHAR(100) NOT NULL DEFAULT '',
        `target_discord_id`       VARCHAR(32) NULL DEFAULT NULL,
        `requester_identifier`    VARCHAR(64) NOT NULL,
        `requester_name`          VARCHAR(100) NOT NULL DEFAULT '',
        `status`                  VARCHAR(20) NOT NULL DEFAULT 'pending',
        `is_repeat`               TINYINT(1) NOT NULL DEFAULT 0,
        `stage`                   INT UNSIGNED NOT NULL DEFAULT 1,
        `created_at`              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `stage_deadline_at`       DATETIME NOT NULL,
        `final_deadline_at`       DATETIME NOT NULL,
        `completed_at`            DATETIME NULL DEFAULT NULL,
        `completed_method`        VARCHAR(10) NULL DEFAULT NULL,
        `completed_by_identifier` VARCHAR(64) NULL DEFAULT NULL,
        PRIMARY KEY (`request_id`),
        KEY `idx_mcpr_target` (`target_identifier`),
        KEY `idx_mcpr_status` (`status`),
        KEY `idx_mcpr_discord` (`target_discord_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
    [[
    CREATE TABLE IF NOT EXISTS `masitz_commands_bans` (
        `identifier` VARCHAR(64) NOT NULL,
        `reason`     VARCHAR(255) NOT NULL DEFAULT '',
        `banned_by`  VARCHAR(100) NOT NULL DEFAULT '',
        `banned_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]],
}

local function EnsureTables()
    for _, definition in ipairs(TABLE_DEFINITIONS) do
        MySQL.query.await(definition)
    end
end

CreateThread(function()
    EnsureTables()
    DatabaseReady = true
    TriggerEvent('Masitz-commands:database:ready')
    DebugPrint('Database klar (tabeller verificeret).')
end)

-- ------------------------------------------------------------------
--  IDENTIFIERS
-- ------------------------------------------------------------------

--- Spillerens stabile identifikator. Bruger ESX' eget xPlayer.identifier
--- (license) når muligt, med et direkte native-opslag som sikkerhedsnet
--- for det korte vindue før ESX har nået at loade spillerens data.
function Helpers.GetIdentifier(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer and xPlayer.identifier then
        return xPlayer.identifier
    end
    return GetPlayerIdentifierByType(source, 'license')
end

--- Samme mønster som Masitz-samfundstjeneste/server/permissions.lua's
--- GetDiscordId - genbruges her for konsistens på tværs af serveren.
function Helpers.GetDiscordId(source)
    if not source or source == 0 then return nil end
    for _, id in ipairs(GetPlayerIdentifiers(source) or {}) do
        if id:find('discord:') then
            return id:gsub('discord:', '')
        end
    end
    return nil
end

function Helpers.GetSteamHex(source)
    for _, id in ipairs(GetPlayerIdentifiers(source) or {}) do
        local hex = id:match('^steam:(%x+)$')
        if hex then return hex end
    end
    return nil
end

--- Konverterer FiveM's steam:HEX til det decimale SteamID64. Lua 5.4 har
--- native 64-bit heltal, så konverteringen er præcis (samme metode som
--- mm-adminpakke/server/steam.lua).
function Helpers.SteamHexToId64(hex)
    if not hex then return nil end
    local ok, num = pcall(tonumber, hex, 16)
    if not ok or not num then return nil end
    return tostring(num)
end

-- ------------------------------------------------------------------
--  PERMISSIONS (samme arkitektur som mm-adminpakke/server/security.lua)
-- ------------------------------------------------------------------
function Helpers.IsStaff(source, cmdConfig)
    if type(source) ~= 'number' then return false end

    if cmdConfig.UseAcePermission then
        return IsPlayerAceAllowed(source, cmdConfig.AcePermission)
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end

    local group = xPlayer.getGroup and xPlayer.getGroup() or nil
    if not group then return false end

    for _, allowed in ipairs(cmdConfig.AllowedGroups or {}) do
        if group == allowed then return true end
    end
    return false
end

-- ------------------------------------------------------------------
--  TARGET-VALIDERING
-- ------------------------------------------------------------------

--- Validér et rå command-argument som et online spiller-ID. Klienten
--- sender kun dette tal - resten (navn, identifiers osv.) slås altid op
--- server-side herfra, aldrig fra klient-leveret data.
function Helpers.ValidateTarget(rawId)
    local id = tonumber(rawId)
    if not id or id ~= math.floor(id) or id < 1 then
        return false, nil, 'Ugyldigt spiller-ID.'
    end
    if not GetPlayerName(id) then
        return false, nil, 'Spiller-ID findes ikke.'
    end
    return true, id, nil
end

-- ------------------------------------------------------------------
--  COOLDOWN / ABUSE-BESKYTTELSE (pr. source, pr. nøgle)
-- ------------------------------------------------------------------
local cooldowns = {}     -- [source.."|"..key] = expiresAtEpoch
local invalidAttempts = {} -- [source.."|"..key] = { count, resetAt }

function Helpers.IsOnCooldown(source, key, seconds)
    local mapKey = tostring(source) .. '|' .. key
    local expiresAt = cooldowns[mapKey]
    local now = os.time()
    if expiresAt and expiresAt > now then
        return true, expiresAt - now
    end
    cooldowns[mapKey] = now + seconds
    return false, 0
end

--- Simpel spam-beskyttelse mod gentagne ugyldige/afviste forsøg (fx
--- forsøg på at ramme ikke-eksisterende ID'er hurtigt efter hinanden).
--- Returnerer true hvis grænsen er nået (kaldet skal da stoppes/logges).
function Helpers.RegisterInvalidAttempt(source, key)
    local mapKey = tostring(source) .. '|' .. key
    local now = os.time()
    local entry = invalidAttempts[mapKey]

    if not entry or now >= entry.resetAt then
        invalidAttempts[mapKey] = { count = 1, resetAt = now + Config.AbuseProtection.WindowSeconds }
        return false
    end

    entry.count = entry.count + 1
    return entry.count > Config.AbuseProtection.MaxInvalidAttempts
end

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for k, v in pairs(cooldowns) do
            if v <= now then cooldowns[k] = nil end
        end
        for k, v in pairs(invalidAttempts) do
            if v.resetAt <= now then invalidAttempts[k] = nil end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local prefix = tostring(source) .. '|'
    for k in pairs(cooldowns) do
        if k:sub(1, #prefix) == prefix then cooldowns[k] = nil end
    end
    for k in pairs(invalidAttempts) do
        if k:sub(1, #prefix) == prefix then invalidAttempts[k] = nil end
    end
end)

-- ------------------------------------------------------------------
--  REQUEST-ID GENERATOR ("POV-20260912-153045-042")
-- ------------------------------------------------------------------
function Helpers.GeneratePovRequestId(targetServerId)
    return ('POV-%s-%03d'):format(os.date('%Y%m%d-%H%M%S'), targetServerId % 1000)
end

-- ------------------------------------------------------------------
--  BAN-HÅNDHÆVELSE (egen, minimal, persistent løsning - der findes
--  ingen eksisterende server-bred ban-resource at integrere med, jf.
--  gennemgangen af de øvrige resources).
-- ------------------------------------------------------------------
function Helpers.IsBanned(identifier)
    local ok, row = pcall(MySQL.single.await,
        'SELECT reason FROM masitz_commands_bans WHERE identifier = ?', { identifier })
    if ok and row then
        return true, row.reason
    end
    return false, nil
end

function Helpers.BanIdentifier(identifier, reason, bannedBy)
    MySQL.query.await([[
        INSERT INTO masitz_commands_bans (identifier, reason, banned_by)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE reason = VALUES(reason), banned_by = VALUES(banned_by), banned_at = CURRENT_TIMESTAMP
    ]], { identifier, reason, bannedBy or 'Masitz-commands' })
end

AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local source = source
    deferrals.defer()

    CreateThread(function()
        Wait(0) -- deferrals kræver mindst én tick før første update

        local identifier = GetPlayerIdentifierByType(source, 'license')
        if not identifier then
            deferrals.done()
            return
        end

        local banned, reason = Helpers.IsBanned(identifier)
        if banned then
            deferrals.done(('Du er permanent udelukket fra serveren.\nÅrsag: %s'):format(reason or 'Ingen årsag angivet'))
            return
        end

        deferrals.done()
    end)
end)
