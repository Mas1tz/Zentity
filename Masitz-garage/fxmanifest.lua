fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Masitz'
description 'Masitz-garage — koeretoejsgarager, baade, impound, salg, noegler, garage-flytning (rework af MM-garage)'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/cl_helpers.lua',
    'client/cl_garage.lua',
    'client/cl_menus.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_helpers.lua',
    'server/sv_logging.lua',
    'server/sv_garage.lua',
    'server/sv_keys.lua',
    'server/sv_sales.lua',
    'server/sv_transfer.lua',
    'server/sv_exports.lua',
}

-- MM-vehiclekeys kaldes udelukkende via exports[...] (pcall-beskyttet),
-- ligesom i den oprindelige resource — ikke listet som hård dependency,
-- så Masitz-garage stadig starter/kører selvom key-scriptet er nede.
dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
    'ox_fuel',
}
