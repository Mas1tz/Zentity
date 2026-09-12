fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Masitz (Rework by KC)'
description 'KC MDT — Premium Police CAD/MDT for ESX Legacy'
version '2.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/sh_sha256.lua',
    'shared/sh_utils.lua',
}

client_scripts {
    'client/cl_polititablet.lua',
    'client/cl_nui.lua',
    'client/cl_events.lua',
    'client/cl_registermdt.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_polititablet.lua',
    'server/sv_auth.lua',
    'server/sv_registermdt.lua',
    'server/sv_dashboard.lua',
    'server/sv_persons.lua',
    'server/sv_vehicles.lua',
    'server/sv_cases.lua',
    'server/sv_dispatch.lua',
    'server/sv_patrol.lua',
    'server/sv_data.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/image/*.png',
    'html/image/*.webp',
    'html/fonts/*.woff2',
    'html/fonts/**/*.woff2',
}

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql',
}