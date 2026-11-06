lib.locale()

--- The config is also exposed as a global, because the framework bridge and the
--- modules read Config.Debug and Config.Notifications directly.
Config = require "config.config"

--- Config.Branding fields and the locale keys they replace
local brandingKeys <const> = {
    title = "title",
    header = "ui.brand",
    bodyModel = "ui.body_model",
    dashModel = "ui.dash_model",
}

---Returns a locale string, or its Config.Branding value when one is set.
---@param key string Locale key (e.g. "title")
---@param ... any Format arguments passed to locale()
---@return string
function BrandedLocale(key, ...)
    for field, localeKey in pairs(brandingKeys) do
        if localeKey == key and Config.Branding and Config.Branding[field] then
            return Config.Branding[field]
        end
    end
    return locale(key, ...)
end

---Returns the locale table with the Config.Branding values applied, for the NUI.
---@return table<string, string>
function GetBrandedLocales()
    local locales = {}
    for key, value in pairs(lib.getLocales()) do locales[key] = value end
    for field, localeKey in pairs(brandingKeys) do
        local value = Config.Branding and Config.Branding[field]
        if value then locales[localeKey] = value end
    end
    return locales
end
