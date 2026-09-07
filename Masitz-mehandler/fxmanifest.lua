fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Masitz-mehandler'
author 'Masitz'
description 'Masitz-mehandler - automatiske /me-handlinger for ESX Legacy + ox_inventory'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/client.lua',
}

server_scripts {
    'server/server.lua',
}

dependencies {
    'ox_lib',
    'ox_inventory',
}
