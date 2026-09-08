fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'mm-christmas'
description 'Premium Christmas Event System'
author      'MM Development'
version     '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/functions.lua',
    'config.lua',
    'locales/da.lua',
    'locales/en.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- Load order matters: later files use globals defined by earlier ones.
    'server/framework.lua',
    'server/inventory.lua',
    'server/currency.lua',
    'server/database.lua',
    'server/ratelimit.lua',
    'server/avatar.lua',
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/assets/*.png',
    'html/assets/*.svg',
}

dependencies {
    'ox_lib',
    'ox_target',
    'oxmysql',
}
