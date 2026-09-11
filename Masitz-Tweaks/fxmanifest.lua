fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Masitz'
description 'Masitz-Tweaks - samlet, performance-optimeret erstatning for disableDispatch, noemergencycars, removeAIcops og disable_radio'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

-- es_extended er IKKE en hård dependency: kun Config.RestrictEmergencyVehicles
-- bruger ESX (til at kende spillerens job), og resten af resourcen fungerer
-- fuldt ud uden noget framework overhovedet. Se README.
