fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Masitz-mysterybox'
author 'Masitz'
description 'Masitz MysteryBox - config-drevet mystery box system til ox_inventory'
version '2.0.0'

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
