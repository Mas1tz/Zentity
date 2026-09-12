fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Masitz'
description 'Masitz-peds - Config-driven PED/NPC framework'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/peds.lua',
    'client/interactions.lua',
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'ox_target',
    'es_extended'
}
