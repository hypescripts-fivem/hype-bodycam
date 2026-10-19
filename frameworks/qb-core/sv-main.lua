---@diagnostic disable: duplicate-set-field
if GetResourceState('qb-core') ~= 'started' then return end
if GetResourceState('qbx_core') == 'started' then return end
if GetResourceState('es_extended') == 'started' then return end

Framework.Server = {}

local QBCore = exports['qb-core']:GetCoreObject()

--- Returns the name of the active framework.
---@return string Always returns "qb-core".
function Framework.Server.GetFrameworkName()
    return 'qb-core'
end

-- Player Actions

--- Returns the server ids of every loaded player.
---@return number[] Array of player server ids.
function Framework.Server.GetPlayers()
    return QBCore.Functions.GetPlayers()
end

exports('GetPlayers', Framework.Server.GetPlayers)

--- Returns the framework player object.
---@param playerId number The player's server id.
---@return table|nil The qb player object, or nil when the player is not loaded.
function Framework.Server.GetPlayer(playerId)
    local Player = QBCore.Functions.GetPlayer(playerId)
    return Player and Player or nil
end

exports('GetPlayer', Framework.Server.GetPlayer)

--- Returns the character name of a player.
---@param playerId number The player's server id.
---@param split boolean|nil True to return firstname and lastname separately.
---@return string|nil name The full name, or the firstname when `split` is true.
---@return string|nil lastname Only returned when `split` is true.
function Framework.Server.GetCharacterName(playerId, split)
    local Player = Framework.Server.GetPlayer(playerId)
    if not Player or not Player.PlayerData or not Player.PlayerData.charinfo then return nil end

    local firstname = Player.PlayerData.charinfo.firstname
    local lastname  = Player.PlayerData.charinfo.lastname

    if split then
        return firstname, lastname
    end

    if not firstname or not lastname then return nil end
    return firstname .. " " .. lastname
end

exports('GetCharacterName', Framework.Server.GetCharacterName)

--- Returns the unique character identifier of a player.
---@param playerId number The player's server id.
---@return string|nil The identifier, or nil when the player is not loaded.
function Framework.Server.GetPlayerIdentifier(playerId)
    local Player = Framework.Server.GetPlayer(playerId)
    return Player and Player.PlayerData and Player.PlayerData.citizenid or nil
end

exports('GetPlayerIdentifier', Framework.Server.GetPlayerIdentifier)

--- Returns the radio callsign of a player, normalised to nil when unset.
---@param playerId number The player's server id.
---@return string|nil The callsign, or nil when the player has none.
function Framework.Server.GetPlayerCallsign(playerId)
    local Player = Framework.Server.GetPlayer(playerId)
    if not Player or not Player.PlayerData or not Player.PlayerData.metadata then return nil end

    local callsign = Player.PlayerData.metadata.callsign
    if not callsign or callsign == "" or callsign == "NO CALLSIGN" then return nil end
    return callsign
end

exports('GetPlayerCallsign', Framework.Server.GetPlayerCallsign)

-- Job Actions

--- Returns a normalised job data table for a player.
---@param playerId number The player's server id.
---@return table|nil A table with fields: name, label, grade.name, grade.level, isBoss, onDuty.
function Framework.Server.GetPlayerJob(playerId)
    local Player = Framework.Server.GetPlayer(playerId)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return nil end

    local jobData = Player.PlayerData.job
    if not jobData.grade then return nil end

    return {
        name   = jobData.name,
        label  = jobData.label,
        grade  = {
            name  = jobData.grade.name,
            level = jobData.grade.level,
        },
        isBoss = jobData.isboss,
        onDuty = jobData.onduty,
    }
end

exports('GetPlayerJob', Framework.Server.GetPlayerJob)

-- Usable Item Actions

--- Registers a usable item handler, normalising the item data across frameworks.
--- This is the path qb-inventory uses for item use.
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
    QBCore.Functions.CreateUseableItem(itemName, func)
end

exports('RegisterUsableItem', Framework.Server.RegisterUsableItem)

-- Inventory Fallback
-- Only used when no supported inventory resource is running, i.e. plain qb-core items.

--- Framework-level inventory lookup, used only without a supported inventory resource.
---@param playerId number The player's server id.
---@param itemName string The item to look for.
---@return table|nil A table with name, slot, count and metadata, or nil when not carried.
function Framework.Server.GetInventoryItem(playerId, itemName)
    local Player = Framework.Server.GetPlayer(playerId)
    if not Player then return nil end

    local item = Player.Functions.GetItemByName(itemName)
    if not item then return nil end

    return {
        name     = item.name,
        slot     = item.slot,
        count    = item.amount or item.count or 1,
        metadata = item.info or {},
    }
end

exports('GetInventoryItem', Framework.Server.GetInventoryItem)

--- Framework-level metadata write, used only without a supported inventory resource.
---@param playerId number The player's server id.
---@param slot number The inventory slot to write to.
---@param metadata table The metadata table to store.
---@return boolean True when the slot was written and the inventory refreshed.
function Framework.Server.SetInventoryItemMetadata(playerId, slot, metadata)
    local Player = Framework.Server.GetPlayer(playerId)
    if not Player or not Player.PlayerData or not Player.PlayerData.items then return false end

    local items = Player.PlayerData.items
    if not items[slot] then return false end

    items[slot].info = metadata
    Player.Functions.SetInventory(items, true)
    return true
end

exports('SetInventoryItemMetadata', Framework.Server.SetInventoryItemMetadata)

return Framework
