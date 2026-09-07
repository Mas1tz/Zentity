fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Masitz-Anticheat'
author 'Masitz'
description 'Masitz-Anticheat - server-authoritative security suite (module: anti-nummerplade)'
version '1.0.0'

-- ============================================================================
-- Dependencies
--
-- es_extended : ESX Legacy — player/identifier/permission handling.
-- oxmysql     : parameterized MySQL access (bans, owned_vehicles, security events).
-- ox_inventory: server-authoritative check/removal of the `vehicle_plate` item.
--
-- ox_lib is intentionally NOT declared as a hard dependency of this module —
-- anti-nummerplade does not call any ox_lib API. It will very likely already
-- be present (ox_inventory depends on it) and future Masitz-Anticheat modules
-- may use it for client-side UI, but this module stays dependency-lean.
-- ============================================================================

dependencies {
    'es_extended',
    'oxmysql',
    'ox_inventory',
}

-- ============================================================================
-- Config (loaded before any module code, on both sides)
-- ============================================================================

shared_scripts {
    'config/anti-nummerplade/config.lua',
}

-- ============================================================================
-- Modules
--
-- Each Masitz-Anticheat module keeps its own client/server pair, isolated in
-- its own folder. Future modules (anti-money, anti-giveitem, anti-vehicle, ...)
-- are added the same way, without touching anti-nummerplade.
-- ============================================================================

client_scripts {
    'client/anti-nummerplade/client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/anti-nummerplade/server.lua',
}
