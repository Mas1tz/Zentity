fx_version 'cerulean'
game 'gta5'

name        'MM-PolitiJob'
author      'Masitz'
description 'Premium Politi Script – ESX/QBCore | ox_lib | ox_target | ox_inventory'
version     '3.1.0'

-- ═══ SHARED ═══
shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

-- ═══ CLIENT ═══
client_scripts {
    '@es_extended/imports.lua',       -- Ignoreres automatisk af QB
    'client/framework.lua',           -- Framework abstraction (indlæses FØRST)
    'client/state.lua',               -- Player state machine
    'client/main.lua',                -- Core: markers, duty, zone
    'client/functions/*.lua'          -- handcuffs, actions, garage, blips, panic, bossmenu, loadout, ...
}

-- ═══ SERVER ═══
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',    -- Server framework abstraction
    'server/database.lua',     -- DB setup + helpers
    'server/handcuffs.lua',    -- Håndjern validering
    'server/Interaktion.lua',      -- GSR, ID, visitering, validering, loadout giveaway
    'server/politigarage.lua',       -- Garage: server-godkendt spawn/park
    'server/Blips.lua',        -- Blip sync
    'server/panikknap.lua',        -- Panic broadcast
    'server/bossmenu.lua',     -- Boss menu callbacks + elevfeedback
    'server/loadout.lua',      -- Politilager shop
    'server/evidence.lua',     -- Evidence stash
    'server/Tackle.lua',      -- Tackle sync
    'server/main.lua',         -- Duty + cleanup + misc
}

-- ═══ NUI (Loadout menu) ═══
ui_page 'html/loadout/index.html'

files {
    'html/loadout/index.html',
    'html/loadout/style.css',
    'html/loadout/app.js',
    'html/loadout/image/*.png'
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_target',
    'ox_inventory',
}