fx_version 'cerulean'
game 'gta5'

author 'MM Scripts'
description 'MM Samfundstjeneste V2'
version '2.0.0-dev'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/permissions.lua',
    'server/players.lua',
    'server/settings.lua',
    'server/trustfactor.lua',
    'server/tasks.lua',
    'server/antiescape.lua',
    'server/identity.lua',
    'server/staff.lua',
    'server/owner.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
    'client/activity.lua',
    'client/service.lua',
    'client/combat.lua',
    'client/tasks.lua',
    'client/antiescape.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
}

lua54 'yes'
