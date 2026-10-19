lib.locale()

--- The config is also exposed as a global, because the framework bridge and the
--- modules read Config.Debug and Config.Notifications directly.
Config = require "config.config"
