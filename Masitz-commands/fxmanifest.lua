fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Masitz-commands'
author 'Masitz'
description 'Standalone /pov, /povdone og /check commands til ESX Legacy'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/discord.lua',
    'server/pov.lua',
    'server/check.lua',
}

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
}
