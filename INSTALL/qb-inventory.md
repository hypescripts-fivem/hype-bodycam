-- qb-inventory / ps-inventory: add this to qb-core/shared/items.lua
-- The image goes to qb-inventory/html/images/bodycam.png (see INSTALL/item-images).
-- Item use runs through the framework usable item, so no client export is needed here.

bodycam = {
    name = 'bodycam',
    label = 'Axon Body 3',
    weight = 250,
    type = 'item',
    image = 'bodycam.png',
    unique = true,
    useable = true,
    shouldClose = true,
    combinable = nil,
    description = 'Police body-worn camera. Use it to start or stop recording.',
},
