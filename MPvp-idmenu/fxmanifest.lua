fx_version 'cerulean'
game 'gta5'

author 'Masitz'
description 'MPvp - Player ID Peek'
version '2.0.0'
lua54 'yes'

-- Rent client-side ID-peek system. Ingen NUI, ingen menu, ingen
-- server-events, og derfor ingen dependencies overhovedet.
shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}
