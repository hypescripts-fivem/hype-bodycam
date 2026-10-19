local Config <const> = require "config.config"

local streams = {} ---@type table<string, table> Stream list last sent by the server, only while recording

local bodycamOn = false
local indicator = nil ---@type string? Last indicator payload sent to the NUI, encoded as json
local localesSent = false
local lightsWatcher = 0

local excludedModels, extraModels = {}, {}
for _, model in ipairs(Config.Dashcam.excluded or {}) do excludedModels[model] = true end
for _, model in ipairs(Config.Dashcam.models or {}) do extraModels[model] = true end

local sidearmExcluded = {}
for _, weapon in ipairs(Config.Signal.sidearm.excluded or {}) do sidearmExcluded[weapon] = true end

Debug("info", "bodycam client loaded: item=%s, dashcam models=%s, excluded models=%s, excluded weapons=%s",
    Config.Item, #(Config.Dashcam.models or {}), #(Config.Dashcam.excluded or {}), #(Config.Signal.sidearm.excluded or {}))

Debug("info", "framework bridge: %s", Framework.Name or "none")

---Checks whether a vehicle carries a dashcam, by configured class or model, minus the excluded models.
---@param vehicle number Vehicle entity handle
---@return boolean dashcam True when the vehicle records
function IsDashcamVehicle(vehicle)
    local model = GetEntityModel(vehicle)
    if excludedModels[model] then
        Debug("info", "vehicle %s has no dashcam: model %s is excluded", vehicle, model)
        return false
    end

    local dashcam = extraModels[model] == true or Config.Dashcam.classes[GetVehicleClass(vehicle)] == true
    Debug("info", "vehicle %s dashcam check: %s (model %s, class %s)", vehicle, dashcam, model, GetVehicleClass(vehicle))
    return dashcam
end

---Client-side pre-check for wearing a bodycam: item in inventory, allowed job, on duty.
---The server has the final say; this only avoids pointless requests.
---@return boolean allowed
local function mayWear()
    if not Framework.Client.GetPlayerJob then
        Debug("error", "wear check failed: no framework bridge is active")
        return false
    end

    local job = Framework.Client.GetPlayerJob()
    local required = job and Config.Access.groups[job.name]
    if required == nil then
        Debug("error", "wear check failed: job %s is not allowed", job and job.name or "none")
        return false
    end

    local grade = job.grade and job.grade.level or 0
    if grade < required then
        Debug("error", "wear check failed: grade %s is below the required %s", grade, required)
        return false
    end

    if Config.Access.requireDuty and job.onDuty ~= true then
        Debug("error", "wear check failed: %s is off duty", job.name)
        return false
    end

    if not Modules.Client.Inventory.HasItem(Config.Item) then
        Debug("error", "wear check failed: no %s in inventory", Config.Item)
        return false
    end

    Debug("success", "wear check passed: %s grade %s", job.name, grade)
    return true
end

---Rebuilds the on-screen Axon indicator from the stream list and pushes it to the NUI.
---Nothing is sent when the payload is unchanged.
---@return nil
local function updateIndicator()
    local body = bodycamOn and streams["b" .. cache.serverId] or nil
    local dash = nil
    if bodycamOn and cache.vehicle and NetworkGetEntityIsNetworked(cache.vehicle) then
        dash = streams["d" .. VehToNet(cache.vehicle)]
    end

    local payload = {
        body = bodycamOn,
        dash = dash ~= nil,
        serial = body and body.serial or nil,
        trigger = body and body.trigger or nil,
        dashSerial = dash and dash.serial or nil,
        dashTrigger = dash and dash.trigger or nil,
        position = Config.UI.indicatorPosition,
    }

    local key = json.encode(payload)
    if key == indicator then return end
    indicator = key

    Debug("info", "indicator changed: body=%s (%s), dash=%s (%s)",
        payload.body, payload.serial or "-", payload.dash, payload.dashSerial or "-")

    if Config.UI.indicator then
        payload.locales = not localesSent and lib.getLocales() or nil
        SendNUIMessage({ action = "nui/indicator", payload = payload })
        Debug("info", "indicator sent to nui (locales attached: %s)", payload.locales ~= nil)
        localesSent = true
    else
        Debug("info", "indicator is disabled in the config, nothing sent")
    end
end

---Waits for a freshly spawned vehicle to get its network id, so VehToNet is safe to call.
---@param vehicle number Vehicle entity handle
---@return boolean networked False on timeout or when the player left the vehicle
local function waitNetworked(vehicle)
    local timeout = GetGameTimer() + 2000
    while not NetworkGetEntityIsNetworked(vehicle) and GetGameTimer() < timeout do Wait(100) end

    if not NetworkGetEntityIsNetworked(vehicle) then
        Debug("warning", "vehicle %s did not get a network id within 2000ms", vehicle)
        return false
    end
    if cache.vehicle ~= vehicle then
        Debug("warning", "vehicle %s got networked, but the player already left it", vehicle)
        return false
    end

    Debug("success", "vehicle %s is networked as %s", vehicle, VehToNet(vehicle))
    return true
end

---Asks the server to start the dashcam of the vehicle the player currently sits in.
---@return nil
local function requestDashcam()
    local vehicle = cache.vehicle
    if not bodycamOn then return Debug("info", "dashcam request skipped: bodycam is off") end
    if not vehicle then return Debug("info", "dashcam request skipped: not in a vehicle") end
    if not IsDashcamVehicle(vehicle) then return Debug("info", "dashcam request skipped: vehicle %s has no dashcam", vehicle) end
    if Config.Dashcam.driverOnly and cache.seat ~= -1 then
        return Debug("info", "dashcam request skipped: driverOnly is on and seat is %s", cache.seat)
    end
    if not waitNetworked(vehicle) then return Debug("error", "dashcam request aborted: vehicle %s is not networked", vehicle) end

    Debug("info", "requesting a dashcam for netId %s", VehToNet(vehicle))
    TriggerServerEvent("hype-bodycam:server:dashcam", VehToNet(vehicle))
end

---Signal Vehicle: watches the siren of the current vehicle while in the driver's seat and
---reports the moment it is switched on. Only one watcher runs at a time.
---@return nil
local function watchLights()
    local vehicle = cache.vehicle
    if not Config.Signal.vehicle.enabled then return Debug("info", "lights watcher skipped: Signal Vehicle is disabled") end
    if not vehicle then return Debug("info", "lights watcher skipped: not in a vehicle") end
    if cache.seat ~= -1 then return Debug("info", "lights watcher skipped: seat %s is not the driver", cache.seat) end
    if not IsDashcamVehicle(vehicle) then return Debug("info", "lights watcher skipped: vehicle %s has no dashcam", vehicle) end

    lightsWatcher = lightsWatcher + 1
    local watcher = lightsWatcher
    Debug("info", "lights watcher %s started for vehicle %s", watcher, vehicle)

    CreateThread(function()
        local wasOn = IsVehicleSirenOn(vehicle)

        while lightsWatcher == watcher and cache.vehicle == vehicle and cache.seat == -1 do
            local on = IsVehicleSirenOn(vehicle)
            if on ~= wasOn then Debug("info", "lights watcher %s: siren is now %s", watcher, on) end

            if on and not wasOn and mayWear() and waitNetworked(vehicle) then
                Debug("info", "lights watcher %s: reporting Signal Vehicle for netId %s", watcher, VehToNet(vehicle))
                TriggerServerEvent("hype-bodycam:server:lights", VehToNet(vehicle))
            end
            wasOn = on
            Wait(300)
        end

        Debug("info", "lights watcher %s stopped", watcher)
    end)
end

---Applies the recording state decided by the server.
---@param active boolean True while the player's bodycam records
---@return nil
RegisterNetEvent("hype-bodycam:client:state", function(active)
    if active == bodycamOn then return Debug("info", "bodycam state unchanged: %s", bodycamOn) end
    bodycamOn = active == true
    Debug("success", "bodycam state changed to %s", bodycamOn)

    updateIndicator()
    if bodycamOn then CreateThread(requestDashcam) end
end)

---Plays an Axon recording beep. Volume falls off with distance for bystanders.
---@param kind "start"|"stop"|"reminder" Beep to play
---@param coords vector3|false Source position, or false when it is the player's own camera
---@return nil
RegisterNetEvent("hype-bodycam:client:beep", function(kind, coords)
    local volume = Config.Beep.volume
    if coords then
        local distance = #(GetEntityCoords(cache.ped) - coords)
        if distance > Config.Beep.range then
            return Debug("info", "beep %s ignored: %.1fm away, range is %.1fm", kind, distance, Config.Beep.range)
        end
        volume = volume * (1.0 - distance / Config.Beep.range) * 0.8
        Debug("info", "beep %s from %.1fm away at volume %.3f", kind, distance, volume)
    else
        Debug("info", "own beep %s at volume %.3f", kind, volume)
    end

    SendNUIMessage({ action = "nui/beep", payload = { kind = kind, volume = volume } })
end)

---Requests a dashcam and refreshes the indicator whenever the player changes vehicle.
---@param vehicle number? Vehicle entity handle, nil on foot
---@return nil
lib.onCache("vehicle", function(vehicle)
    cache.vehicle = vehicle
    Debug("info", "vehicle cache changed to %s", vehicle or "none")
    if vehicle then CreateThread(requestDashcam) end
    SetTimeout(0, updateIndicator)
end)

---Starts the siren watcher and, in driverOnly mode, the dashcam once the player takes the wheel.
---@param seat number? Seat index, -1 for the driver
---@return nil
lib.onCache("seat", function(seat)
    cache.seat = seat
    Debug("info", "seat cache changed to %s", seat or "none")
    if seat == -1 then watchLights() end
    if Config.Dashcam.driverOnly and seat == -1 then CreateThread(requestDashcam) end
end)

---Signal Sidearm: asks the server to start recording when a firearm is drawn.
---@param weapon number? Weapon hash held by the ped
---@return nil
lib.onCache("weapon", function(weapon)
    if not weapon then return end
    if bodycamOn then return Debug("info", "Signal Sidearm skipped: already recording") end
    if not Config.Signal.sidearm.enabled then return Debug("info", "Signal Sidearm skipped: disabled in the config") end
    if sidearmExcluded[weapon] then return Debug("info", "Signal Sidearm skipped: weapon %s is excluded", weapon) end

    SetTimeout(0, function()
        if not IsPedArmed(cache.ped, 4) then return Debug("info", "Signal Sidearm skipped: weapon %s is not a firearm", weapon) end
        if not mayWear() then return Debug("info", "Signal Sidearm skipped: wear check failed") end

        Debug("info", "reporting Signal Sidearm for weapon %s", weapon)
        TriggerServerEvent("hype-bodycam:server:sidearm")
    end)
end)

---Refreshes the indicator when the server sends a new stream list.
---@param list table<string, table>? New stream map
---@return nil
RegisterNetEvent("hype-bodycam:client:streams", function(list)
    streams = list or {}
    SetTimeout(0, updateIndicator)
end)

---ox_inventory item use export, wired up in data/items.lua as client.export = "hype-bodycam.bodycam".
---Every other inventory uses the framework usable item registered on the server instead.
---@param _ table Item data, unused
---@param slot table? Slot the item was used from
---@return nil
exports("bodycam", function(_, slot)
    Debug("info", "%s used from slot %s, asking the server to toggle", Config.Item, slot and slot.slot or "unknown")
    TriggerServerEvent("hype-bodycam:server:toggle", slot and slot.slot)
end)

---Reports whether the local player's bodycam is recording.
---@return boolean recording
exports("IsBodycamOn", function()
    Debug("info", "export IsBodycamOn: %s", bodycamOn)
    return bodycamOn
end)
