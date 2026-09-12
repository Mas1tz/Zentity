fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Masitz'
description 'MPvp - Weapon Hub'
version '2.0.0'

-- Ren NUI weapon hub. Ingen ox_lib-afhængighed — ingen context-menu,
-- inputDialog eller notify bruges længere, så der er intet tilbage
-- ox_lib reelt skulle levere.
client_scripts {
    'config.lua',
    'client.lua'
}

server_scripts {
    'config.lua',
    'server.lua'
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

dependencies {
    'ox_inventory'
}
