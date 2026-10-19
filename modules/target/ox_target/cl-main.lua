---@diagnostic disable: duplicate-set-field
local resourceName = "ox_target"
if GetResourceState(resourceName) == 'missing' then return end

Modules.Client.Target = {}

local ox_target = exports.ox_target
local targetZones = {}

--- Normalises a target options array for ox_target compatibility.
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

--- Creates a sphere-shaped target zone at the given world coordinates.
---@param name string A unique identifier for this zone used for later removal.
---@param coords vector3 The centre position of the sphere in world space.
---@param radius number The radius of the sphere zone in metres.
---@param options table Array of target option tables to attach to the zone.
---@return number|nil The ox_target zone ID, or nil when options is empty.
function Modules.Client.Target.AddSphereZone(name, coords, radius, options)
    options = fixOptions(options or {})
    if not next(options) then return end

    local target = ox_target:addSphereZone({
        coords = coords,
        radius = radius,
        name = name,
        debug = Config.Debug,
        options = options
    })

    targetZones[#targetZones + 1] = { name = name, id = target, creator = GetInvokingResource() }

    return target
end

exports("AddSphereZone", Modules.Client.Target.AddSphereZone)

--- Removes a previously created target zone by its name.
---@param name string The unique zone name passed to AddSphereZone.
---@return nil
function Modules.Client.Target.RemoveZone(name)
    if not name then return end

    for index, data in ipairs(targetZones) do
        if data.name == name then
            ox_target:removeZone(data.id)
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
            ox_target:removeZone(target.id)
            table.remove(targetZones, index)
        end
    end
end)
