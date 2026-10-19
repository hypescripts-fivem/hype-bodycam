local QB_STYLE <const> = {
    ['qb-inventory'] = true,
    ['ps-inventory'] = true,
}

local SUPPORTED <const> = {
    'ox_inventory',
    'qb-inventory',
    'ps-inventory',
    'codem-inventory',
    'core_inventory',
    'jpr-inventory',
    'origen_inventory',
    'tgiann-inventory',
}

local resolved = nil
local warned = false

--- Returns the name of the running inventory resource, cached once one is found.
--- Returns nil when none is running, in which case the framework fallback is used.
--- A miss is not cached, so an inventory that starts later is still picked up.
---@return string|nil The inventory resource name, or nil for the framework fallback.
local function inventory()
    if resolved then return resolved end

    for _, name in ipairs(SUPPORTED) do
        if GetResourceState(name) == 'started' then
            resolved = name
            Debug("info", "inventory module bound to %s", name)
            return resolved
        end
    end

    if not warned then
        warned = true
        Debug("warning", "no supported inventory found, falling back to the framework inventory")
    end
    return nil
end

--- Reads an item through the framework, the last resort when no inventory resource runs.
---@param playerId number The server-side player source ID.
---@param itemName string The internal name of the item to find.
---@return table|nil A table with name, slot, count and metadata, or nil when unavailable.
local function frameworkItem(playerId, itemName)
    if not Framework.Server.GetInventoryItem then
        Debug("error", "no framework bridge is active, cannot read the inventory")
        return nil
    end

    return Framework.Server.GetInventoryItem(playerId, itemName)
end

--- Checks whether a player has the specified item(s) in their inventory.
--- Supports: codem-inventory, core_inventory, jpr-inventory, origen_inventory,
--- ox_inventory, ps-inventory, qb-inventory, tgiann-inventory, plus the framework fallback.
---@param playerId number The server-side player source ID.
---@param items string|table A single item name (string) or a key-value table of { [itemName] = requiredCount }.
---@param count number|nil The required quantity when `items` is a string. Ignored when `items` is a table.
---@return boolean True if the player has the required item(s), false otherwise.
function Modules.Server.Inventory.HasItem(playerId, items, count)
    count = count or 1
    local name = inventory()

    if name == 'ox_inventory' then
        if type(items) == 'table' then
            for itemName, itemCount in pairs(items) do
                if exports.ox_inventory:GetItemCount(playerId, itemName) < itemCount then return false end
            end

            return true
        end

        return exports.ox_inventory:GetItemCount(playerId, items) >= count
    elseif name == 'origen_inventory' then
        if type(items) == 'table' then
            for itemName, itemCount in pairs(items) do
                if not exports.origen_inventory:HasItem(playerId, itemName, itemCount) then return false end
            end

            return true
        end

        return exports.origen_inventory:HasItem(playerId, items, count)
    elseif name == 'core_inventory' then
        return exports['core_inventory']:hasItem(playerId, items, count)
    elseif name then
        return exports[name]:HasItem(playerId, items, count)
    end

    if type(items) == 'table' then
        for itemName, itemCount in pairs(items) do
            local item = frameworkItem(playerId, itemName)
            if not item or item.count < itemCount then return false end
        end

        return true
    end

    local item = frameworkItem(playerId, items)
    return item ~= nil and item.count >= count
end

exports('HasItem', Modules.Server.Inventory.HasItem)

lib.callback.register('hype-bodycam:server:has-item', function(source, items, count)
    if not source then return false end

    return Modules.Server.Inventory.HasItem(source, items, count)
end)

--- Returns how many of an item a player carries.
--- Inventories without a count export fall back to a presence check, so they
--- report 1 instead of the real amount.
---@param playerId number The server-side player source ID.
---@param itemName string The internal name of the item to count.
---@return number The amount carried, or 0 when the player has none.
function Modules.Server.Inventory.GetItemCount(playerId, itemName)
    local name = inventory()

    if name == 'ox_inventory' then
        return exports.ox_inventory:GetItemCount(playerId, itemName) or 0
    elseif QB_STYLE[name] then
        local item = exports[name]:GetItemByName(playerId, itemName)
        return item and (item.amount or item.count or 0) or 0
    elseif name then
        return Modules.Server.Inventory.HasItem(playerId, itemName, 1) and 1 or 0
    end

    local item = frameworkItem(playerId, itemName)
    return item and item.count or 0
end

exports('GetItemCount', Modules.Server.Inventory.GetItemCount)

--- Returns a single item a player carries, normalised across inventories.
--- Looks in `slot` first and searches the inventory by name when that slot holds
--- something else, which is what item-use callbacks need.
---@param playerId number The server-side player source ID.
---@param itemName string The internal name of the item to find.
---@param slot number|nil The slot to look in first, e.g. the slot the item was used from.
---@return table|nil A table with name, slot, count and metadata, or nil when the player has none.
function Modules.Server.Inventory.GetItem(playerId, itemName, slot)
    local name = inventory()

    if name == 'ox_inventory' then
        local item = slot and exports.ox_inventory:GetSlot(playerId, slot)
        if not item or item.name ~= itemName then
            item = exports.ox_inventory:GetSlotWithItem(playerId, itemName)
        end
        if not item then return nil end

        return {
            name     = item.name,
            slot     = item.slot,
            count    = item.count or 1,
            metadata = item.metadata or {},
        }
    elseif QB_STYLE[name] then
        local item = slot and exports[name]:GetItemBySlot(playerId, slot)
        if not item or item.name ~= itemName then
            item = exports[name]:GetItemByName(playerId, itemName)
        end
        if not item then return nil end

        return {
            name     = item.name,
            slot     = item.slot,
            count    = item.amount or item.count or 1,
            metadata = item.info or {},
        }
    elseif name then
        Debug("warning", "%s cannot expose item slots, device serials will not persist", name)
        return nil
    end

    return frameworkItem(playerId, itemName)
end

exports('GetItem', Modules.Server.Inventory.GetItem)

--- Writes metadata onto one of a player's items.
--- Used to store a device serial on the item it belongs to.
---@param playerId number The server-side player source ID.
---@param item table An item table returned by GetItem.
---@param metadata table The metadata table to store.
---@return boolean True when the inventory accepted the write.
function Modules.Server.Inventory.SetItemMetadata(playerId, item, metadata)
    if not item then return false end
    local name = inventory()

    if name == 'ox_inventory' then
        exports.ox_inventory:SetMetadata(playerId, item.slot, metadata)
        return true
    elseif QB_STYLE[name] then
        exports[name]:SetItemData(playerId, item.name, 'info', metadata)
        return true
    elseif name then
        Debug("warning", "%s does not support metadata writes from this script", name)
        return false
    end

    if not item.slot or not Framework.Server.SetInventoryItemMetadata then return false end
    return Framework.Server.SetInventoryItemMetadata(playerId, item.slot, metadata) == true
end

exports('SetItemMetadata', Modules.Server.Inventory.SetItemMetadata)

--- Registers a hook that fills in the metadata of a newly created item.
--- Only ox_inventory exposes item creation; elsewhere the caller has to assign
--- the metadata on first use instead.
---@param itemName string The item to hook.
---@param cb fun(metadata: table): table Receives the item's metadata and returns the metadata to store.
---@return boolean True when the hook was registered.
function Modules.Server.Inventory.OnItemCreated(itemName, cb)
    if inventory() ~= 'ox_inventory' then
        Debug("info", "item creation hooks need ox_inventory, %s metadata is assigned on first use", itemName)
        return false
    end

    exports.ox_inventory:registerHook("createItem", function(payload)
        return cb(payload.metadata or {})
    end, { itemFilter = { [itemName] = true } })

    return true
end

exports('OnItemCreated', Modules.Server.Inventory.OnItemCreated)
