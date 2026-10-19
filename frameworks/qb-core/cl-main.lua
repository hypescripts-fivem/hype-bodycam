---@diagnostic disable: duplicate-set-field
if GetResourceState('qb-core') ~= 'started' then return end
if GetResourceState('qbx_core') == 'started' then return end
if GetResourceState('es_extended') == 'started' then return end

Framework.Client = {}

local QBCore = exports['qb-core']:GetCoreObject()

--- Returns the name of the active framework.
---@return string Always returns "qb-core".
function Framework.Client.GetFrameworkName()
    return 'qb-core'
end

-- Player Actions

--- Returns the full player data object for the local player.
---@return table|nil The PlayerData table containing job, gang, money, charinfo, metadata, etc.
function Framework.Client.GetPlayerData()
    return QBCore.Functions.GetPlayerData() or nil
end

exports('GetPlayerData', Framework.Client.GetPlayerData)

-- Job Actions

--- Returns a normalised job data table for the local player.
---@return table|nil A table with fields: name, label, grade.name, grade.level, isBoss, onDuty.
function Framework.Client.GetPlayerJob()
    local PlayerData = Framework.Client.GetPlayerData()
    if not PlayerData or not PlayerData.job or not PlayerData.job.grade then return nil end

    local jobData = PlayerData.job

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

exports('GetPlayerJob', Framework.Client.GetPlayerJob)

return Framework
