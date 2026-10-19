---@diagnostic disable: duplicate-set-field
if GetResourceState('es_extended') ~= 'started' then return end

Framework.Server = {}

local ESX = exports.es_extended:getSharedObject()

--- Returns the name of the active framework.
---@return string Always returns "es_extended".
function Framework.Server.GetFrameworkName()
    return 'es_extended'
end

-- Player Actions

--- Returns the server ids of every loaded player.
---@return number[] Array of player server ids.
function Framework.Server.GetPlayers()
    local players = {}
    for _, xPlayer in pairs(ESX.GetExtendedPlayers()) do
        players[#players + 1] = xPlayer.source
    end
    return players
end

exports('GetPlayers', Framework.Server.GetPlayers)

--- Returns the framework player object.
---@param playerId number The player's server id.
---@return table|nil The xPlayer object, or nil when the player is not loaded.
function Framework.Server.GetPlayer(playerId)
    local Player = ESX.GetPlayerFromId(playerId)
    return Player and Player or nil
end

exports('GetPlayer', Framework.Server.GetPlayer)

--- Returns the character name of a player.
--- ESX stores one display name, so `split` returns the first and last word of it.
---@param playerId number The player's server id.
---@param split boolean|nil True to return firstname and lastname separately.
---@return string|nil name The full name, or the firstname when `split` is true.
---@return string|nil lastname Only returned when `split` is true.
function Framework.Server.GetCharacterName(playerId, split)
    local Player = Framework.Server.GetPlayer(playerId)
    if not Player then return nil end

    local name = Player.getName()
    if not name then return nil end

    if split then
        local firstname, lastname = name:match("^(%S+)%s+(.*)$")
        return firstname or name, lastname
    end

    return name
end

exports('GetCharacterName', Framework.Server.GetCharacterName)

--- Returns the unique character identifier of a player.
---@param playerId number The player's server id.
---@return string|nil The identifier, or nil when the player is not loaded.
function Framework.Server.GetPlayerIdentifier(playerId)
    local Player = Framework.Server.GetPlayer(playerId)
    if not Player then return nil end
    return Player.getIdentifier() or nil
end

exports('GetPlayerIdentifier', Framework.Server.GetPlayerIdentifier)

--- Returns the radio callsign of a player, normalised to nil when unset.
--- ESX has no callsign field, so the `callsign` metadata is read when a resource sets it.
---@param playerId number The player's server id.
---@return string|nil The callsign, or nil when the player has none.
function Framework.Server.GetPlayerCallsign(playerId)
    local Player = Framework.Server.GetPlayer(playerId)
    if not Player or not Player.getMeta then return nil end

    local callsign = Player.getMeta('callsign')
    if type(callsign) ~= "string" or callsign == "" or callsign == "NO CALLSIGN" then return nil end
    return callsign
end

exports('GetPlayerCallsign', Framework.Server.GetPlayerCallsign)

-- Job Actions

--- Returns a normalised job data table for a player.
--- ESX has no duty system, so `onDuty` reads the `onDuty` metadata when a job
--- resource sets it and reports true otherwise.
---@param playerId number The player's server id.
---@return table|nil A table with fields: name, label, grade.name, grade.level, isBoss, onDuty.
function Framework.Server.GetPlayerJob(playerId)
    local Player = Framework.Server.GetPlayer(playerId)
    if not Player or not Player.job then return nil end

    local jobData = Player.job
    if not jobData.grade then return nil end

    local duty = Player.getMeta and Player.getMeta('onDuty')

    return {
        name   = jobData.name,
        label  = jobData.label,
        grade  = {
            name  = jobData.grade_name,
            level = jobData.grade,
        },
        isBoss = jobData.grade_name == "boss",
        onDuty = duty == nil and true or duty == true,
    }
end

exports('GetPlayerJob', Framework.Server.GetPlayerJob)

-- Usable Item Actions

--- Registers a usable item handler, normalising the item data across frameworks.
--- Inventories that handle item use themselves (ox_inventory) ignore this.
---@param itemName string The item to register.
---@param cb fun(playerId: number, itemData: table) Called with the player's id and the used item.
---@return nil
function Framework.Server.RegisterUsableItem(itemName, cb)
    local func = function(playerId, item, itemData)
        itemData = itemData or item
        itemData.metadata = itemData.metadata or itemData.info or {}
        itemData.slot = itemData.id or itemData.slot
        cb(playerId, itemData)
    end
    ESX.RegisterUsableItem(itemName, func)
end

exports('RegisterUsableItem', Framework.Server.RegisterUsableItem)

-- Inventory Fallback
-- Only used when no supported inventory resource is running, i.e. the built-in ESX inventory.

--- Framework-level inventory lookup, used only without a supported inventory resource.
--- The built-in ESX inventory has no slots or metadata, so only the count is real.
---@param playerId number The player's server id.
---@param itemName string The item to look for.
---@return table|nil A table with name, slot, count and metadata, or nil when not carried.
function Framework.Server.GetInventoryItem(playerId, itemName)
    local Player = Framework.Server.GetPlayer(playerId)
    if not Player then return nil end

    local item = Player.getInventoryItem(itemName)
    if not item or (item.count or 0) < 1 then return nil end

    return {
        name     = item.name,
        slot     = nil,
        count    = item.count,
        metadata = {},
    }
end

exports('GetInventoryItem', Framework.Server.GetInventoryItem)

--- Framework-level metadata write, used only without a supported inventory resource.
--- The built-in ESX inventory cannot store per-item metadata.
---@param playerId number The player's server id.
---@param slot number The inventory slot to write to.
---@param metadata table The metadata table to store.
---@return boolean Always false on the built-in ESX inventory.
function Framework.Server.SetInventoryItemMetadata(playerId, slot, metadata)
    warn("the built-in ESX inventory cannot store item metadata; use ox_inventory to keep device serials")
    return false
end

exports('SetInventoryItemMetadata', Framework.Server.SetInventoryItemMetadata)

return Framework
