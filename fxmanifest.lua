fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Mazus / MZ Core'
description 'MZ World Editor - ferramenta dev/admin para inspecionar entidades e criar portas/props'
version '0.3.0'

shared_scripts {
    'shared/config.lua'
}

client_scripts {
    'client/utils.lua',
    'client/raycast.lua',
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}
