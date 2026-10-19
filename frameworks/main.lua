Framework = {
    Name = nil,
    Server = {},
    Client = {}
}

if GetResourceState('es_extended') == 'started' then
    Framework.Name = 'es_extended'
elseif GetResourceState('qbx_core') == 'started' then
    Framework.Name = 'qbx_core'
elseif GetResourceState('qb-core') == 'started' then
    Framework.Name = 'qb-core'
else
    print('^1[hype-bodycam] No supported framework found. Start es_extended, qbx_core or qb-core.^0')
end

--- Returns the framework bridge for the current side.
--- Exported as `GetFrameworkObject` for use by other resources.
---@return table The Framework.Server table on the server, Framework.Client on the client.
if IsDuplicityVersion() then
    exports('GetFrameworkObject', function()
        return Framework.Server
    end)
else
    exports('GetFrameworkObject', function()
        return Framework.Client
    end)
end
