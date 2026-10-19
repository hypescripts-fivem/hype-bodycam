-- es_extended: the item lives in the database when no standalone inventory is used.
-- Running ox_inventory instead? Use INSTALL/ox-inventory.lua and skip this file.
--
-- Item use is registered through ESX.RegisterUsableItem by the framework bridge,
-- so nothing else has to be declared for it.
--
-- Item image: copy INSTALL/item-images/bodycam.png into your inventory resource,
-- e.g. esx_inventoryhud/html/img/items/bodycam.png (path depends on the resource).

-- ESX Legacy (items table with a weight column)
INSERT INTO `items` (`name`, `label`, `weight`, `rare`, `can_remove`) VALUES
    ('bodycam', 'Axon Body 3', 1, 0, 1)
ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `weight` = VALUES(`weight`);

-- Older ESX (items table with a limit column) - use this instead of the insert above
-- INSERT INTO `items` (`name`, `label`, `limit`, `rare`, `can_remove`) VALUES
--     ('bodycam', 'Axon Body 3', 1, 0, 1)
-- ON DUPLICATE KEY UPDATE `label` = VALUES(`label`);

-- Note: the built-in ESX inventory stores no per-item metadata, so a device serial
-- cannot be written onto the item. The script then derives a stable serial from the
-- character identifier, which means every bodycam of one officer reports the same
-- serial. Run ox_inventory if you want a serial per physical item.
