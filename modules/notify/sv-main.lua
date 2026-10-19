--- Sends a UI notification to a player from the server.
--- Uses the client notify module, so the configured `Config.Notifications` resource is respected.
---@param playerId number The server-side player source ID. Pass -1 to notify everyone.
---@param title string The notification title displayed in the header.
---@param message string The notification body text.
---@param time number|nil Duration in milliseconds. Defaults to 5000.
---@param type string|nil The notification type (e.g. "success", "error", "inform", "warning"). Defaults to "success".
---@return nil
function Modules.Server.Notify.SendNotify(playerId, title, message, time, type)
    TriggerClientEvent("hype-bodycam:client:send-notify", playerId, title, message, time, type)
end

exports("SendNotify", Modules.Server.Notify.SendNotify)
