--- Checks whether the local player has the specified item(s), using the server inventory bridge.
---@param items string|table A single item name (string) or a key-value table of { [itemName] = requiredCount }.
---@param count number|nil The required quantity when `items` is a string. Defaults to 1.
---@return boolean True if the player has the required item(s), false otherwise.
function Modules.Client.Inventory.HasItem(items, count)
    return lib.callback.await('hype-bodycam:server:has-item', false, items, count or 1) or false
end

exports("HasItem", Modules.Client.Inventory.HasItem)
