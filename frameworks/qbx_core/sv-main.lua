---@diagnostic disable: duplicate-set-field
if GetResourceState('qbx_core') ~= 'started' then return end
if GetResourceState('es_extended') == 'started' then return end

Framework.Server = {}

local QBX = exports.qbx_core

--- Returns the name of the active framework.
---@return string Always returns "qbx_core".
function Framework.Server.GetFrameworkName()
    return 'qbx_core'
end

-- Player Actions

--- Returns the server ids of every loaded player.
---@return number[] Array of player server ids.
function Framework.Server.GetPlayers()
    local players = QBX:GetQBPlayers()
    local filteredPlayers = {}
    for _, player in pairs(players) do
        filteredPlayers[#filteredPlayers + 1] = player.PlayerData.source
    end
    return filteredPlayers
end

exports('GetPlayers', Framework.Server.GetPlayers)

--- Returns the framework player object.
---@param playerId number The player's server id.
---@return table|nil The qbx player object, or nil when the player is not loaded.
function Framework.Server.GetPlayer(playerId)
    local Player = QBX:GetPlayer(playerId)
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
--- Inventories that handle item use themselves (ox_inventory) ignore this.
---@param itemName string The item to register.
---@param cb fun(playerId: number, itemData: table) Called with the player's id and the used item.
---@return any The framework's registration result.
function Framework.Server.RegisterUsableItem(itemName, cb)
    local func = function(playerId, item, itemData)
        itemData = itemData or item
        itemData.metadata = itemData.metadata or itemData.info or {}
        itemData.slot = itemData.id or itemData.slot
        cb(playerId, itemData)
    end
    return QBX:CreateUseableItem(itemName, func)
end

exports('RegisterUsableItem', Framework.Server.RegisterUsableItem)

-- Inventory Fallback
-- Only used when no supported inventory resource is running. qbx_core always ships
-- with ox_inventory, so the inventory module handles it and these stay unsupported.

--- Framework-level inventory lookup, used only without a supported inventory resource.
---@param playerId number The player's server id.
---@param itemName string The item to look for.
---@return table|nil Always nil on qbx_core.
function Framework.Server.GetInventoryItem(playerId, itemName)
    warn("qbx_core requires ox_inventory; no framework inventory fallback is available")
    return nil
end

exports('GetInventoryItem', Framework.Server.GetInventoryItem)

--- Framework-level metadata write, used only without a supported inventory resource.
---@param playerId number The player's server id.
---@param slot number The inventory slot to write to.
---@param metadata table The metadata table to store.
---@return boolean Always false on qbx_core.
function Framework.Server.SetInventoryItemMetadata(playerId, slot, metadata)
    warn("qbx_core requires ox_inventory; item metadata cannot be written without it")
    return false
end

exports('SetInventoryItemMetadata', Framework.Server.SetInventoryItemMetadata)

return Framework
