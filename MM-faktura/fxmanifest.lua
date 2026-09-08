fx_version 'cerulean'
game 'gta5'

author 'Masitz'
description 'Faktura Tablet V2'

version '2.0.0'

ui_page 'html/index.html'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua'
}

client_scripts {
  'client/cl_faktura.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/sv_faktura.lua'
}

files {
  'html/index.html',
  'html/css/style.css',
  'html/js/script.js',
  'html/image/Mmasitz.png'
}

dependency 'ox_lib'
dependency 'oxmysql'
