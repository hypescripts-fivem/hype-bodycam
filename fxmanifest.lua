fx_version 'cerulean'
game {'gta5'}

author 'vezironi'
description 'One Bodycam is an Axon style bodycam & dashcam system for FiveM servers. On duty officers switch their bodycam on with an item, police vehicles start recording automatically when they get in, and authorized players watch live feeds from police station terminals.'

scriptname 'hype-bodycam'
version '1.0.0'

dependencies {
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config/*.lua',
    'shared/*.lua',
    'frameworks/main.lua',
    'modules/main.lua',
}

client_scripts {
    'frameworks/**/cl-main.lua',
    'modules/inventory/cl-main.lua',
    'modules/notify/cl-main.lua',
    'modules/target/**/cl-*.lua',
    'client/*.lua',
}

server_scripts {
    'frameworks/**/sv-main.lua',
    'modules/inventory/sv-main.lua',
    'modules/notify/sv-main.lua',
    'server/*.lua',
}

escrow_ignore {
    'config/*.lua',
    'shared/*.lua',
    'frameworks/**/*.lua',
    'frameworks/main.lua',
    'modules/**/**.lua',
    'modules/main.lua',
    'client/*.lua',
    'server/*.lua',
}

files {
    'web/build/*.*',
    'web/build/**/*.*',
    'locales/*.json',
}

ui_page 'web/build/index.html'

lua54 'yes'
use_experimental_fxv2_oal 'yes'
