--[[
    Settings-modulet gør en afgrænset delmængde af Config.Samfundstjeneste
    RUNTIME-redigerbar fra Owner-dashboardet, uden at kræve en resource-
    genstart. Værdierne caches i hukommelsen (læst fra sf_settings ved
    boot) og enhver ændring skrives igennem til databasen med det samme.

    Config.lua er stadig "sandheden" for alt der IKKE er registreret her
    (fx sites, task-punkter, animationer) — de kræver bevidst en filredigering
    + genstart, fordi de involverer koordinater/props der bør gennemtjekkes
    af en udvikler, ikke ændres i farten fra en UI-knap.
]]

Settings = {}

local cache = {}

-- Definerer HVILKE nøgler der må ændres fra Owner-UI'en, deres default
-- (hentet fra Config første gang) og en simpel valideringsfunktion.
local SCHEMA = {
    trustFactorMode = {
        default = function() return Config.Samfundstjeneste.TrustFactor.mode end,
        validate = function(v) return v == 'per_task' or v == 'per_x_tasks' end,
    },
    trustFactorPerTaskLoss = {
        default = function() return Config.Samfundstjeneste.TrustFactor.perTask.loss end,
        validate = function(v) return type(v) == 'number' and v >= 0 and v <= 100 end,
    },
    trustFactorPerXTasksTasks = {
        default = function() return Config.Samfundstjeneste.TrustFactor.perXTasks.tasks end,
        validate = function(v) return type(v) == 'number' and v >= 1 end,
    },
    trustFactorPerXTasksLoss = {
        default = function() return Config.Samfundstjeneste.TrustFactor.perXTasks.loss end,
        validate = function(v) return type(v) == 'number' and v >= 0 and v <= 100 end,
    },
    trustFactorRecoveryEnabled = {
        default = function() return Config.Samfundstjeneste.TrustFactor.recovery.enabled end,
        validate = function(v) return type(v) == 'boolean' end,
    },
    trustFactorRecoveryMinutes = {
        default = function() return Config.Samfundstjeneste.TrustFactor.recovery.requiredActiveMinutes end,
        validate = function(v) return type(v) == 'number' and v >= 1 end,
    },
    trustFactorRecoveryAmount = {
        default = function() return Config.Samfundstjeneste.TrustFactor.recovery.recoveryAmount end,
        validate = function(v) return type(v) == 'number' and v > 0 and v <= 100 end,
    },
    trustFactorAfkTimeout = {
        default = function() return Config.Samfundstjeneste.TrustFactor.recovery.afkTimeoutSeconds end,
        validate = function(v) return type(v) == 'number' and v >= 10 end,
    },
    timeReductionEnabled = {
        default = function() return Config.Samfundstjeneste.TimeReduction.enabled end,
        validate = function(v) return type(v) == 'boolean' end,
    },
    timeReductionInterval = {
        default = function() return Config.Samfundstjeneste.TimeReduction.interval end,
        validate = function(v) return type(v) == 'number' and v >= 5 end,
    },
    timeReductionAmount = {
        default = function() return Config.Samfundstjeneste.TimeReduction.amount end,
        validate = function(v) return type(v) == 'number' and v >= 1 end,
    },
    antiEscapeEnabled = {
        default = function() return Config.Samfundstjeneste.AntiEscape.enabled end,
        validate = function(v) return type(v) == 'boolean' end,
    },
    antiEscapePauseDuration = {
        default = function() return Config.Samfundstjeneste.AntiEscape.taskPauseDuration end,
        validate = function(v) return type(v) == 'number' and v >= 0 end,
    },
}

function Settings.Get(key)
    if cache[key] ~= nil then return cache[key] end

    local schema = SCHEMA[key]
    if not schema then return nil end

    cache[key] = schema.default()
    return cache[key]
end

-- Bekvemme genveje der bruges konstant af trustfactor.lua / tasks.lua,
-- så de aldrig behøver kende til de rå settings-nøgler.
function Settings.TrustFactor()
    return {
        enabled = Config.Samfundstjeneste.TrustFactor.enabled,
        mode = Settings.Get('trustFactorMode'),
        perTaskLoss = Settings.Get('trustFactorPerTaskLoss'),
        perXTasksTasks = Settings.Get('trustFactorPerXTasksTasks'),
        perXTasksLoss = Settings.Get('trustFactorPerXTasksLoss'),
        recoveryEnabled = Settings.Get('trustFactorRecoveryEnabled'),
        recoveryMinutes = Settings.Get('trustFactorRecoveryMinutes'),
        recoveryAmount = Settings.Get('trustFactorRecoveryAmount'),
        afkTimeoutSeconds = Settings.Get('trustFactorAfkTimeout'),
    }
end

function Settings.TimeReduction()
    return {
        enabled = Settings.Get('timeReductionEnabled'),
        interval = Settings.Get('timeReductionInterval'),
        amount = Settings.Get('timeReductionAmount'),
    }
end

function Settings.AntiEscape()
    return {
        enabled = Settings.Get('antiEscapeEnabled'),
        pauseDuration = Settings.Get('antiEscapePauseDuration'),
    }
end

function Settings.Set(key, value, actorIdentifier, actorName)
    local schema = SCHEMA[key]
    if not schema then return false, 'ukendt indstilling' end
    if not schema.validate(value) then return false, 'ugyldig værdi' end

    cache[key] = value

    if DatabaseReady then
        exports.oxmysql:insert(
            'INSERT INTO sf_settings (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)',
            { key, Utils.SafeJsonEncode({ value = value }) }
        )
    end

    InsertAuditLog('change_config', actorIdentifier, actorName, nil, nil, { key = key, value = value })

    return true
end

function Settings.GetAllForUI()
    local out = {}
    for key in pairs(SCHEMA) do
        out[key] = Settings.Get(key)
    end
    return out
end

-- ------------------------------------------------------------
-- LOAD VED BOOT
-- ------------------------------------------------------------
AddEventHandler('mm_sf:database:ready', function()
    local rows = exports.oxmysql:querySync('SELECT setting_key, setting_value FROM sf_settings', {})
    for _, row in ipairs(rows or {}) do
        if SCHEMA[row.setting_key] then
            local decoded = Utils.SafeJsonDecode(row.setting_value)
            if decoded and decoded.value ~= nil then
                cache[row.setting_key] = decoded.value
            end
        end
    end
end)
