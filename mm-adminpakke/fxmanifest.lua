fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mm-adminpakke'
author 'Masitz'
description 'MM Adminpakke V2 - moderne admin-panel til ESX Legacy + ox_inventory'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/tablet.lua',
}

server_scripts {
    'server/security.lua',
    'server/players.lua',
    'server/items.lua',
    'server/steam.lua',
    'server/logs.lua',
    'server/actions.lua',
    'server/main.lua',
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/css/main.css',
    'nui/css/components.css',
    'nui/js/app.js',
    'nui/js/players.js',
    'nui/js/items.js',
    'nui/js/components.js',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
}
