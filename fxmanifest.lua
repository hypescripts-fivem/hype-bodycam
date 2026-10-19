fx_version 'cerulean'
game {'gta5'}

author 'vezironi'
description 'One Bodycam is an Axon style bodycam & dashcam system for FiveM servers. On duty officers switch their bodycam on with an item, police vehicles start recording automatically when they get in, and authorized players watch live feeds from police station terminals.'

scriptname 'hype-bodycam'
version '1.0.0'

-- Frameworks: es_extended, qbx_core, qb-core (auto detected)
-- Inventories: ox_inventory, qb-inventory and the other bridges in modules/inventory
-- Targets: ox_target, qb-target
dependencies {
    'ox_lib',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/*.lua',
    'frameworks/main.lua',
    'modules/main.lua',
}

client_scripts {
    'frameworks/*/cl-main.lua',
    'modules/inventory/cl-main.lua',
    'modules/notify/cl-main.lua',
    'modules/target/*/cl-main.lua',
    'client/*.lua',
}

server_scripts {
    'frameworks/*/sv-main.lua',
    'modules/inventory/sv-main.lua',
    'modules/notify/sv-main.lua',
    'server/*.lua',
}

files {
    'config/*.lua',
    'web/build/*.*',
    'web/build/**/*.*',
    'locales/*.json',
}

ui_page 'web/build/index.html'

lua54 'yes'
use_experimental_fxv2_oal 'yes'
