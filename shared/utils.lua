local Config <const> = require "config.config"

local debugStatus <const> = {
    ["success"] = "^2[SUCCESS]^0",
    ["error"] = "^1[ERROR]^0",
    ["warning"] = "^3[WARNING]^0",
    ["info"] = "^4[INFO]^0",
}

local context <const> = IsDuplicityVersion() and "SERVER" or "CLIENT"

---@param status "success"|"error"|"warning"|"info"
---@param message string
---@param ... any
function Debug(status, message, ...)
    if not Config.Debug then return end

    local prefix = debugStatus[status] or ("^7[" .. tostring(status) .. "]^0")
    local body = tostring(message or "")

    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, body, ...)
        body = ok and formatted or body
    end

    print("[DEBUG:" .. context .. "] " .. prefix .. " " .. body)
end
