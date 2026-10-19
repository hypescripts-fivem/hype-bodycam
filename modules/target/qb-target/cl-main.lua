---@diagnostic disable: duplicate-set-field
local resourceName = "qb-target"
if GetResourceState(resourceName) == 'missing' then return end
if GetResourceState("ox_target") ~= 'missing' then return end

Modules.Client.Target = {}

local qb_target = exports['qb-target']
local targetZones = {}

--- Normalises a target options array for qb-target compatibility.
--- Remaps `onSelect`/`action` to a unified handler, converts server events,
--- and syncs `job`/`groups` fields.
---@param options table Array of target option tables to normalise.
---@return table The same options array with normalised fields.
local function fixOptions(options)
    for index, option in pairs(options) do
        local action = option.onSelect or option.action

        if action then
            local select = function(entityOrData)
                if type(entityOrData) == "table" then
                    return action(entityOrData.entity)
                end

                return action(entityOrData)
            end
            options[index].action = select

            options[index].onSelect = select
        else
            if option.type == "server" and option.event then
                options[index].serverEvent = option.event
                options[index].event = nil
            end
        end

        options[index].job = option.job or option.groups
        options[index].groups = option.groups or option.job

        options[index].jobType = option.jobType

        if option.canInteract then
            options[index].canInteract = option.canInteract
        end
    end

    return options
end

--- Scans a target options array and returns the largest `distance` value found.
--- Used to set the interaction distance of qb-target zones.
---@param data table Array of target option tables, each optionally containing a `distance` field.
---@return number The largest distance value found, or 2.0 when none are specified.
local function getLargestDistance(data)
    local largestDistance = -1
    for _, v in pairs(data) do
        if v.distance and v.distance > largestDistance then
            largestDistance = v.distance
        end
    end
    return largestDistance ~= -1 and largestDistance or 2.0
end

--- Creates a sphere-shaped target zone at the given world coordinates.
---@param name string A unique identifier for this zone used for later removal.
---@param coords vector3 The centre position of the sphere in world space.
---@param radius number The radius of the sphere zone in metres.
---@param options table Array of target option tables to attach to the zone.
---@return string|nil The zone name, or nil when options is empty.
function Modules.Client.Target.AddSphereZone(name, coords, radius, options)
    options = fixOptions(options or {})
    if not next(options) then return end

    qb_target:AddCircleZone(name, coords, radius, {
        name = name,
        debugPoly = Config.Debug,
    }, {
        options = options,
        distance = getLargestDistance(options),
    })

    targetZones[#targetZones + 1] = { name = name, creator = GetInvokingResource() }

    return name
end

exports("AddSphereZone", Modules.Client.Target.AddSphereZone)

--- Removes a previously created target zone by its name.
---@param name string The unique zone name passed to AddSphereZone.
---@return nil
function Modules.Client.Target.RemoveZone(name)
    if not name then return end

    for index, data in ipairs(targetZones) do
        if data.name == name then
            qb_target:RemoveZone(name)
            table.remove(targetZones, index)
            break
        end
    end
end

exports("RemoveZone", Modules.Client.Target.RemoveZone)

-- Zones may be registered on behalf of another resource, so clean those up when it stops.
AddEventHandler('onResourceStop', function(resource)
    local isSelf = resource == GetCurrentResourceName()

    for index = #targetZones, 1, -1 do
        local target = targetZones[index]
        if isSelf or target.creator == resource then
            qb_target:RemoveZone(target.name)
            table.remove(targetZones, index)
        end
    end
end)
