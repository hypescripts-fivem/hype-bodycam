---@diagnostic disable: duplicate-set-field
if GetResourceState('es_extended') ~= 'started' then return end

Framework.Client = {}

local ESX = exports.es_extended:getSharedObject()

--- Returns the name of the active framework.
---@return string Always returns "es_extended".
function Framework.Client.GetFrameworkName()
    return 'es_extended'
end

-- Player Actions

--- Returns the full player data object for the local player.
---@return table|nil The ESX PlayerData table containing job, accounts, inventory, etc.
function Framework.Client.GetPlayerData()
    return ESX.GetPlayerData() or nil
end

exports('GetPlayerData', Framework.Client.GetPlayerData)

-- Job Actions

--- Returns a normalised job data table for the local player.
--- ESX has no duty system on the client, so `onDuty` is always true and the server
--- side decides whether duty is required.
---@return table|nil A table with fields: name, label, grade.name, grade.level, isBoss, onDuty.
function Framework.Client.GetPlayerJob()
    local PlayerData = Framework.Client.GetPlayerData()
    if not PlayerData or not PlayerData.job or not PlayerData.job.grade then return nil end

    local jobData = PlayerData.job

    return {
        name   = jobData.name,
        label  = jobData.label,
        grade  = {
            name  = jobData.grade_name,
            level = jobData.grade,
        },
        isBoss = jobData.grade_name == "boss",
        onDuty = true,
    }
end

exports('GetPlayerJob', Framework.Client.GetPlayerJob)

return Framework
