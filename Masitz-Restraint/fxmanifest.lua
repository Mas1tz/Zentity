fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Masitz-Restraint'
author 'Masitz'
description 'Masitz-Restraint - server-authoritative restraint/carry/drag system for ESX Legacy'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    'server/sv_restraint.lua',
}

client_scripts {
    'client/cl_restraint.lua',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
}
