Modules = {
    Server = {
        Inventory = {},
        Notify = {},
    },
    Client = {
        Inventory = {},
        Notify = {},
        Target = {},
    }
}

--- Returns the Modules table or a specific side's module group.
--- Exported as `GetModules` for use by other resources.
---@param targetModule string|nil Pass "Server" or "Client" to get only that side's modules. Pass nil to get the full Modules table.
---@return table The requested module group or the full Modules table.
exports('GetModules', function(targetModule)
    local isServer = IsDuplicityVersion() and 'Server' or 'Client'
    if targetModule and Modules[isServer][targetModule] then
        return Modules[isServer][targetModule]
    end

    return Modules[isServer]
end)
