--- Notification type names differ per resource, so they are normalised per target.
local TYPES <const> = {
    ox_lib    = { info = "inform" },
    okokNotify = { inform = "info" },
    ["ps-ui"]  = { inform = "info" },
}

--- Returns the active notification resource, honouring Config.Notifications.
---@return string|nil The resource name, or nil when none is available.
local function provider()
    local configured = Config.Notifications or "auto"
    if configured ~= "auto" then
        return GetResourceState(configured) == "started" and configured or nil
    end

    for _, name in ipairs({ "okokNotify", "ps-ui", "ox_lib" }) do
        if GetResourceState(name) == "started" then return name end
    end

    return nil
end

--- Sends a UI notification to the local player using the configured notification resource.
--- Supports: okokNotify, ps-ui, ox_lib. The active system is determined by
--- `Config.Notifications` ("auto" auto-detects).
---@param title string The notification title displayed in the header.
---@param message string The notification body text.
---@param time number|nil Duration in milliseconds the notification stays visible. Defaults to 5000.
---@param type string|nil The notification style/type (e.g. "success", "error", "inform", "warning"). Defaults to "success".
---@return nil
function Modules.Client.Notify.SendNotify(title, message, time, type)
    type = type or "success"
    time = time or 5000

    local resource = provider()
    if not resource then
        return Debug("error", "no supported notification system found, dropping: %s", message)
    end

    type = TYPES[resource] and TYPES[resource][type] or type
    Debug("info", "notify through %s (%s): %s", resource, type, message)

    if resource == "okokNotify" then
        exports["okokNotify"]:Alert(title, message, time, type)
    elseif resource == "ps-ui" then
        exports["ps-ui"]:Notify(message, type, time)
    else
        exports["ox_lib"]:notify({
            title = title,
            description = message,
            type = type,
            duration = time,
        })
    end
end

exports("SendNotify", Modules.Client.Notify.SendNotify)

RegisterNetEvent("hype-bodycam:client:send-notify", function(...)
    Modules.Client.Notify.SendNotify(...)
end)
