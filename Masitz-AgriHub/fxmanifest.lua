fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Masitz'
description 'Masitz-AgriHub - Agricultural & Logistics Network'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/vehicles.lua',
    'client/tasks.lua',
    'client/rental.lua',
    'client/nui.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/logging.lua',
    'server/access.lua',
    'server/vehicles.lua',
    'server/shop.lua',
    'server/tasks.lua',
    'server/rental.lua',
    'server/exports.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
    'web/assets/*.png',
    'web/assets/*.svg',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'oxmysql',
}

-- MM-vehiclekeys kaldes udelukkende via pcall-beskyttede exports (se
-- server/vehicles.lua) — IKKE en hård dependency, så Masitz-AgriHub
-- stadig starter selvom key-scriptet skulle være nede. Se README.
