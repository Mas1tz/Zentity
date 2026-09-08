fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Masitz-InventoryLogs'
author 'Masitz'
description 'Enterprise inventory audit logging for ESX Legacy + ox_inventory (Discord + database)'
version '1.0.0'

-- Server-only resource: this script never registers a client script, a NUI
-- page, or any exposed server event/callback that accepts data from a client.
-- Everything logged comes from ox_inventory's own server-side hook payloads
-- or from server-authoritative lookups (ESX player objects, natives), so
-- there is no surface for a client to spoof a log entry.

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- optional: only touched when Config.Storage ~= 'discord'
    'server/utils.lua',
    'server/framework.lua',
    'server/database.lua',
    'server/discord.lua',
    'server/logger.lua',
    'server/hooks.lua',
    'server/main.lua',
}

-- oxmysql is intentionally NOT listed here so the resource still starts and
-- runs in Discord-only mode on servers that don't run oxmysql. If
-- Config.Storage is 'database' or 'both', oxmysql must be installed and
-- started before this resource (see README.md).
dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
}
