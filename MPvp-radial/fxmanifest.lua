fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Masitz'
description 'MPvp - Radial (Noclip / Revive / Lobby / Report)'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'ox_lib'
}

-- ox_target og es_extended er fjernet — ingen af dem blev reelt brugt.
-- Revive kalder stadig esx_ambulancejob:revive (uændret integration),
-- men det er bevidst et BLØDT kald (TriggerEvent, ikke en hård
-- dependency): findes resourcen ikke, no-op'er det bare i stedet for
-- at forhindre MPvp-radial i at starte overhovedet.
