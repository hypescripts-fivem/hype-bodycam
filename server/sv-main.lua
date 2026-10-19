local Config <const> = require "config.config"

local scriptName <const> = GetCurrentResourceName()

local TICK <const> = 1000
local VALIDATE_EVERY <const> = 3
local SUMMARY_EVERY <const> = 10
local TOGGLE_COOLDOWN <const> = 1500
local SIGNAL_COOLDOWN <const> = 3000

---@alias Trigger "manual"|"sidearm"|"vehicle"|"entry"|"lights"

---@class Stream
---@field id string
---@field type "body"|"dash"
---@field owner number Bodycam: the officer. Dashcam: the (last) officer in the vehicle
---@field name string
---@field callsign string?
---@field job string?
---@field grade string?
---@field serial string Device serial number (X + 8 digits)
---@field trigger Trigger Event that started the recording
---@field startedAt number os.time
---@field netId number? Dashcam only
---@field plate string? Dashcam only
---@field model number? Dashcam only
---@field lights boolean? Dashcam only

---@type table<string, Stream>
local streams = {}
---@type table<number, string> Viewer source to stream id
local viewers = {}
---@type table<number, true> Players with the stream list open, they receive every list update
local subscribers = {}
local lastToggle, lastSignal, lastBeep = {}, {}, {}

local excludedModels = {}
for _, model in ipairs(Config.Dashcam.excluded or {}) do excludedModels[model] = true end

local sidearmExcluded = {}
for _, weapon in ipairs(Config.Signal.sidearm.excluded or {}) do sidearmExcluded[weapon] = true end

Debug("info", "bodycam server loaded: item=%s, requireDuty=%s/%s, ace=%s, Signal Sidearm=%s, Signal Vehicle=%s (%sm), beep=%s (%ss)",
    Config.Item, Config.Access.requireDuty, Config.ViewAccess.requireDuty, Config.ViewAccess.ace or "off",
    Config.Signal.sidearm.enabled, Config.Signal.vehicle.enabled, Config.Signal.vehicle.range,
    Config.Beep.enabled, Config.Beep.interval)

Debug("info", "framework bridge: %s", Framework.Name or "none")

---Logs a suspicious request to the server console with the player's name and id.
---@param source number Player server id
---@param message string Format string
---@param ... any Format arguments
---@return nil
local function suspicious(source, message, ...)
    local ok, text = pcall(string.format, message, ...)
    print(("^3[%s] Suspicious request from ^7%s (%s): %s^0"):format(scriptName, GetPlayerName(source) or "?", source, ok and text or message))
end

---Sends a notification to a player through the notify module, so the resource
---configured in Config.Notifications is used.
---@param source number Player server id
---@param description string Text to display
---@param notifyType string? Notification type, defaults to "inform"
---@return nil
local function notify(source, description, notifyType)
    Debug("info", "notify %s (%s): %s", source, notifyType or "inform", description)
    Modules.Server.Notify.SendNotify(source, locale("title"), description, 5000, notifyType or "inform")
end

---Builds the stream id of a player's bodycam.
---@param source number Player server id
---@return string id
local function bodyId(source) return "b" .. source end

---Builds the stream id of a vehicle's dashcam.
---@param netId number Vehicle network id
---@return string id
local function dashId(netId) return "d" .. netId end

---Rate limit helper: records the current time per key and reports whether the
---previous call is still within the given window.
---@param store table<any, number> Timestamp store
---@param key any Entry key
---@param ms number Window in milliseconds
---@return boolean blocked
local function cooldown(store, key, ms)
    local now = GetGameTimer()
    if store[key] and now - store[key] < ms then
        Debug("warning", "cooldown hit for %s: %sms of %sms elapsed", key, now - store[key], ms)
        return true
    end
    store[key] = now
    return false
end

---Checks a player against an access block from the config.
---@param source number Player server id
---@param access table Config.Access or Config.ViewAccess
---@return boolean allowed
local function groupCheck(source, access)
    if not Framework.Server.GetPlayerJob then
        Debug("error", "group check failed: no framework bridge is active")
        return false
    end

    local job = Framework.Server.GetPlayerJob(source)
    if not job then
        Debug("error", "group check failed for %s: no player or job data", source)
        return false
    end

    local required = access.groups[job.name]
    if required == nil then
        Debug("error", "group check for %s: job %s is not in the allowed list", source, job.name)
        return false
    end

    local grade = job.grade and job.grade.level or 0
    if grade < required then
        Debug("error", "group check for %s: grade %s of job %s is below the required %s", source, grade, job.name, required)
        return false
    end

    if access.requireDuty and job.onDuty ~= true then
        Debug("error", "group check for %s: job %s is not on duty", source, job.name)
        return false
    end

    Debug("success", "group check for %s: job=%s, grade=%s, onDuty=%s -> true", source, job.name, grade, job.onDuty)
    return true
end

---Checks whether a player may record: allowed job plus the item in their inventory.
---@param source number Player server id
---@return boolean allowed
local function canWear(source)
    if not groupCheck(source, Config.Access) then return false end

    local count = Modules.Server.Inventory.GetItemCount(source, Config.Item)
    if count < 1 then
        Debug("error", "%s may not record: no %s in inventory", source, Config.Item)
        return false
    end

    Debug("success", "%s may record: %s x%s", source, Config.Item, count)
    return true
end

---Checks whether a player may watch streams, by ace or by job.
---@param source number Player server id
---@return boolean allowed
local function canView(source)
    local access = Config.ViewAccess
    if access.ace and IsPlayerAceAllowed(source, access.ace) then
        Debug("success", "%s may watch through the ace %s", source, access.ace)
        return true
    end
    return groupCheck(source, access)
end

---Checks whether a player stands at a viewing terminal. Always true when the stream
---list can also be opened by command.
---@param source number Player server id
---@return boolean nearby
local function atTerminal(source)
    if Config.Command then return true end

    local ped = GetPlayerPed(source)
    if ped == 0 then return false end

    local coords = GetEntityCoords(ped)
    for _, terminal in ipairs(Config.Terminals) do
        -- 1m of tolerance over the client limit for position sync delay
        if #(coords - terminal.coords) <= Config.TerminalDistance + 1.0 then return true end
    end

    Debug("warning", "%s is not at a terminal", source)
    return false
end

---Generates a random bodycam serial number.
---@return string serial
local function newBodySerial()
    local serial = ("%s%04d"):format(Config.Serial.body, math.random(0, 9999))
    Debug("info", "new bodycam serial generated: %s", serial)
    return serial
end

---Derives a Fleet serial from the plate, so a vehicle always reports the same serial.
---@param plate string Vehicle plate, may be empty
---@param netId number Vehicle network id, used when the plate is empty
---@return string serial
local function fleetSerial(plate, netId)
    local seed = plate ~= "" and plate or tostring(netId)
    local serial = ("%s%04d"):format(Config.Serial.fleet, (joaat(seed) & 0x7FFFFFFF) % 10000)
    Debug("info", "fleet serial %s derived from %s", serial, seed)
    return serial
end

---Derives a serial from the character identifier, for inventories that cannot store
---item metadata (the built-in ESX inventory). Every bodycam of one officer then
---reports the same serial, but it stays the same between uses and restarts.
---@param source number Player server id
---@return string serial
local function characterSerial(source)
    local identifier = Framework.Server.GetPlayerIdentifier and Framework.Server.GetPlayerIdentifier(source)
    if not identifier then
        Debug("warning", "%s has no identifier, falling back to a random serial", source)
        return newBodySerial()
    end

    local serial = ("%s%04d"):format(Config.Serial.body, (joaat(identifier) & 0x7FFFFFFF) % 10000)
    Debug("info", "serial %s derived from the character identifier of %s", serial, source)
    return serial
end

---Reads the serial from the officer's bodycam item, assigning one to older items
---that do not have it yet. Inventories that cannot store metadata fall back to the
---character serial.
---@param source number Player server id
---@param slot number? Slot of the item that was used
---@return string serial
local function itemSerial(source, slot)
    local item = Modules.Server.Inventory.GetItem(source, Config.Item, slot)
    if not item then
        Debug("warning", "%s has no readable %s item, using the character serial", source, Config.Item)
        return characterSerial(source)
    end

    local metadata = item.metadata or {}
    if metadata.serial then
        Debug("info", "%s is recording with serial %s from slot %s", source, metadata.serial, item.slot or "?")
        return metadata.serial
    end

    metadata.serial = newBodySerial()
    if Modules.Server.Inventory.SetItemMetadata(source, item, metadata) then
        Debug("info", "serial %s written to the %s of %s in slot %s", metadata.serial, Config.Item, source, item.slot or "?")
        return metadata.serial
    end

    local serial = characterSerial(source)
    Debug("warning", "this inventory cannot store metadata, using the character serial %s instead", serial)
    return serial
end

---Gives every newly created bodycam item a random serial number. Only ox_inventory
---exposes item creation; with every other inventory the serial is assigned on first
---use. Registration is deferred so the inventory resource is up before it is detected.
---@return nil
CreateThread(function()
    Wait(1000)

    Modules.Server.Inventory.OnItemCreated(Config.Item, function(metadata)
        if not metadata.serial then metadata.serial = newBodySerial() end
        Debug("info", "%s item created with serial %s", Config.Item, metadata.serial)
        return metadata
    end)
end)

---Plays a recording beep for the officer and every player within range.
---@param source number Player server id of the officer
---@param kind "start"|"stop"|"reminder" Beep to play
---@return nil
local function beep(source, kind)
    local beepConfig = Config.Beep
    if not beepConfig.enabled then return Debug("info", "beep %s skipped: beeps are disabled", kind) end

    local ped = GetPlayerPed(source)
    if ped == 0 then return Debug("warning", "beep %s skipped: %s has no ped", kind, source) end
    local coords = GetEntityCoords(ped)

    local reached = 0
    for _, player in ipairs(Framework.Server.GetPlayers()) do
        player = tonumber(player)
        local other = GetPlayerPed(player)

        if player == source or (other ~= 0 and #(GetEntityCoords(other) - coords) <= beepConfig.range) then
            TriggerClientEvent("hype-bodycam:client:beep", player, kind, player == source and false or coords)
            reached = reached + 1
        end
    end

    Debug("info", "beep %s of %s sent to %s players within %sm", kind, source, reached, beepConfig.range)
end

---Sends the stream list only to the players who need it: those with the list open,
---and recording officers for their indicator.
---@return nil
local function publish()
    local targets = {}
    for subscriber in pairs(subscribers) do targets[subscriber] = true end

    local body, dash = 0, 0
    for _, stream in pairs(streams) do
        if stream.type == "body" then
            body = body + 1
            targets[stream.owner] = true
        else
            dash = dash + 1
        end
    end

    local sent = 0
    for target in pairs(targets) do
        TriggerClientEvent("hype-bodycam:client:streams", target, streams)
        sent = sent + 1
    end
    Debug("info", "stream list published to %s players: %s bodycam, %s dashcam", sent, body, dash)
end

---Collects the character details shown on a stream.
---@param source number Player server id
---@return string name
---@return string? callsign
---@return string? job Job label
---@return string? grade Grade name
local function officerInfo(source)
    local name = Framework.Server.GetCharacterName(source)
    if not name or name == "" then
        name = GetPlayerName(source) or ("#" .. source)
        Debug("warning", "%s has no character name, falling back to %s", source, name)
    end

    local callsign = Framework.Server.GetPlayerCallsign(source)
    local job = Framework.Server.GetPlayerJob(source)

    Debug("info", "officer details for %s: %s, callsign %s, job %s", source, name, callsign or "-", job and job.name or "-")
    return name, callsign, job and job.label, job and job.grade and job.grade.name
end

---Tells a client whether its own bodycam is recording.
---@param source number Player server id
---@return nil
local function sendState(source)
    local active = streams[bodyId(source)] ~= nil
    Debug("info", "sending bodycam state %s to %s", active, source)
    TriggerClientEvent("hype-bodycam:client:state", source, active)
end

---Stops a stream, notifies its viewers and fires hype-bodycam:server:streamStopped
---for logging resources: AddEventHandler("hype-bodycam:server:streamStopped", function(stream, reason) end)
---@param id string Stream id
---@param reason string? Reason recorded in the log and the event
---@return nil
local function stopStream(id, reason)
    local stream = streams[id]
    if not stream then return Debug("warning", "stop requested for unknown stream %s (%s)", id, reason or "?") end

    streams[id] = nil
    lastBeep[id] = nil
    publish()

    local notified = 0
    for viewer, watching in pairs(viewers) do
        if watching == id then
            TriggerClientEvent("hype-bodycam:client:ended", viewer, id)
            notified = notified + 1
        end
    end

    TriggerEvent("hype-bodycam:server:streamStopped", stream, reason)
    Debug("info", "%s stream %s of %s stopped after %ss (%s), %s viewers notified",
        stream.type, id, stream.name, os.time() - (stream.startedAt or os.time()), reason or "?", notified)
end

---Returns the vehicle a player sits in.
---@param source number Player server id
---@return number vehicle Entity handle, 0 when on foot
local function vehicleOf(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return 0 end
    return GetVehiclePedIsIn(ped, false)
end

---Finds an officer inside the vehicle whose bodycam is recording, favouring the
---preferred one when they are still aboard.
---@param vehicle number Vehicle entity handle
---@param preferred number? Player server id to keep if possible
---@return number? source Player server id, nil when there is none
local function officerInside(vehicle, preferred)
    if preferred and streams[bodyId(preferred)] and vehicleOf(preferred) == vehicle then return preferred end

    for _, stream in pairs(streams) do
        if stream.type == "body" and vehicleOf(stream.owner) == vehicle then
            Debug("info", "vehicle %s is now covered by %s", vehicle, stream.owner)
            return stream.owner
        end
    end
    return nil
end

---Starts a player's bodycam stream and plays the start beep.
---@param source number Player server id
---@param trigger Trigger Event that started the recording
---@param slot number? Slot of the item that was used
---@return nil
local function startBodycam(source, trigger, slot)
    local name, callsign, job, grade = officerInfo(source)
    local id = bodyId(source)

    streams[id] = {
        id = id,
        type = "body",
        owner = source,
        name = name,
        callsign = callsign,
        job = job,
        grade = grade,
        serial = itemSerial(source, slot),
        trigger = trigger,
        startedAt = os.time(),
    }
    lastBeep[id] = os.time()
    publish()
    sendState(source)
    beep(source, "start")

    TriggerEvent("hype-bodycam:server:streamStarted", streams[id])
    Debug("success", "bodycam %s started for %s (%s), serial %s, trigger %s", id, name, source, streams[id].serial, trigger)
end

---Stops a player's bodycam. Dashcams they own are handed over to another recording
---officer in the vehicle, or stopped when there is none.
---@param source number Player server id
---@param reason string? Reason recorded in the log and the event
---@return nil
local function stopBodycam(source, reason)
    local id = bodyId(source)
    if not streams[id] then return Debug("info", "stop skipped: %s has no running bodycam", source) end

    stopStream(id, reason)
    if reason ~= "dropped" then beep(source, "stop") end

    for dash, stream in pairs(streams) do
        if stream.type == "dash" and stream.owner == source then
            local vehicle = NetworkGetEntityFromNetworkId(stream.netId)
            local other = vehicle ~= 0 and officerInside(vehicle)

            if other then
                Debug("info", "dashcam %s handed over from %s to %s", dash, source, other)
                stream.owner = other
                stream.name, stream.callsign, stream.job = officerInfo(other)
                publish()
            else
                Debug("info", "dashcam %s has no other recording officer aboard", dash)
                stopStream(dash, "owner_" .. (reason or "off"))
            end
        end
    end

    sendState(source)
end

---Starts a vehicle's dashcam stream. A vehicle already recording is left alone;
---its ownership moves to an officer inside through the validation loop.
---@param source number Player server id of the officer in the vehicle
---@param netId number Vehicle network id
---@return nil
local function startDashcam(source, netId)
    local id = dashId(netId)
    if streams[id] then return Debug("info", "dashcam %s is already recording, ownership is handled by the loop", id) end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local name, callsign, job = officerInfo(source)
    local plate = (GetVehicleNumberPlateText(vehicle) or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local lights = IsVehicleSirenOn(vehicle)

    streams[id] = {
        id = id,
        type = "dash",
        owner = source,
        name = name,
        callsign = callsign,
        job = job,
        serial = fleetSerial(plate, netId),
        trigger = lights and "lights" or "entry",
        startedAt = os.time(),
        netId = netId,
        plate = plate,
        model = GetEntityModel(vehicle),
        lights = lights,
    }
    publish()

    TriggerEvent("hype-bodycam:server:streamStarted", streams[id])
    Debug("success", "dashcam %s started by %s: plate %s, serial %s, lights %s, trigger %s",
        id, source, plate ~= "" and plate or "-", streams[id].serial, lights, streams[id].trigger)
end

---Current world position of a stream's ped or vehicle.
---@param stream Stream Stream entry
---@return vector3? coords Nil when the entity no longer exists
local function streamCoords(stream)
    local entity = stream.type == "body" and GetPlayerPed(stream.owner) or NetworkGetEntityFromNetworkId(stream.netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        Debug("warning", "stream %s has no live entity", stream.id)
        return nil
    end
    return GetEntityCoords(entity)
end

---Validates a dashcam request: the entity must be a vehicle, the player must be
---inside it, and the model must not be excluded.
---@param source number Player server id
---@param netId number|string Vehicle network id sent by the client
---@return number vehicle Entity handle, 0 when invalid
local function validVehicle(source, netId)
    netId = tonumber(netId)
    local vehicle = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        Debug("error", "netId %s from %s is not a live vehicle", netId or "nil", source)
        return 0
    end

    if vehicleOf(source) ~= vehicle then
        suspicious(source, "request for a vehicle they are not in: %s", netId)
        return 0
    end
    if excludedModels[GetEntityModel(vehicle)] then
        suspicious(source, "vehicle model without a dashcam: %s", netId)
        return 0
    end

    Debug("success", "vehicle %s (netId %s) accepted for %s", vehicle, netId, source)
    return vehicle
end

---Switches a player's bodycam on or off after an item use.
---@param src number Player server id
---@param slot number? Slot the item was used from
---@return nil
local function toggleBodycam(src, slot)
    Debug("info", "%s used the %s item from slot %s", src, Config.Item, slot or "nil")
    if cooldown(lastToggle, src, TOGGLE_COOLDOWN) then return end

    if streams[bodyId(src)] then
        stopBodycam(src, "off")
        return notify(src, locale("notify.body_off"), "inform")
    end

    if not groupCheck(src, Config.Access) then
        Debug("error", "toggle denied for %s: no wear access", src)
        return notify(src, locale("notify.no_wear_access"), "error")
    end
    if Modules.Server.Inventory.GetItemCount(src, Config.Item) < 1 then
        return suspicious(src, "bodycam toggle request without the item")
    end

    startBodycam(src, "manual", tonumber(slot))
    notify(src, locale("notify.body_on"), "success")
end

---ox_inventory runs the client export from its item definition, which lands here.
---@param slot number? Slot the item was used from
---@return nil
RegisterNetEvent("hype-bodycam:server:toggle", function(slot)
    toggleBodycam(source, slot)
end)

---Every other inventory routes item use through the framework, so register there too.
---@param playerId number Player server id
---@param itemData table The used item, normalised by the framework bridge
---@return nil
if Framework.Server.RegisterUsableItem then
    Framework.Server.RegisterUsableItem(Config.Item, function(playerId, itemData)
        toggleBodycam(playerId, itemData and itemData.slot)
    end)
else
    Debug("error", "no framework bridge is active, the %s item cannot be registered", Config.Item)
end

---Signal Sidearm: starts recording after a firearm was drawn.
---@return nil
RegisterNetEvent("hype-bodycam:server:sidearm", function()
    local src = source
    Debug("info", "Signal Sidearm reported by %s", src)

    if not Config.Signal.sidearm.enabled then return Debug("info", "Signal Sidearm ignored: disabled in the config") end
    if streams[bodyId(src)] then return Debug("info", "Signal Sidearm ignored: %s is already recording", src) end
    if cooldown(lastSignal, src, SIGNAL_COOLDOWN) then return end
    if not canWear(src) then return Debug("error", "Signal Sidearm denied for %s", src) end

    local weapon = GetSelectedPedWeapon(GetPlayerPed(src))
    if weapon == `WEAPON_UNARMED` then return Debug("warning", "Signal Sidearm ignored: %s holds no weapon", src) end
    if sidearmExcluded[weapon] then return Debug("info", "Signal Sidearm ignored: weapon %s is excluded", weapon) end

    startBodycam(src, "sidearm")
    notify(src, locale("notify.signal_sidearm"), "warning")
end)

---Signal Vehicle: lights went on, so every eligible officer in and around the
---vehicle starts recording.
---@param netId number Vehicle network id
---@return nil
RegisterNetEvent("hype-bodycam:server:lights", function(netId)
    local src = source
    local signal = Config.Signal.vehicle
    Debug("info", "Signal Vehicle reported by %s for netId %s", src, netId)

    if not signal.enabled then return Debug("info", "Signal Vehicle ignored: disabled in the config") end
    if not groupCheck(src, Config.Access) then return Debug("error", "Signal Vehicle denied for %s", src) end

    local vehicle = validVehicle(src, netId)
    if vehicle == 0 then return end
    if not IsVehicleSirenOn(vehicle) then return Debug("warning", "Signal Vehicle ignored: the siren of %s is off", netId) end
    if cooldown(lastSignal, "v" .. netId, SIGNAL_COOLDOWN) then return end

    local coords = GetEntityCoords(vehicle)
    local started = 0
    for _, player in ipairs(Framework.Server.GetPlayers()) do
        player = tonumber(player)
        local ped = GetPlayerPed(player)

        if ped ~= 0 and not streams[bodyId(player)] and #(GetEntityCoords(ped) - coords) <= signal.range and canWear(player) then
            startBodycam(player, "vehicle")
            notify(player, locale("notify.signal_vehicle"), "warning")
            started = started + 1
        end
    end

    Debug("success", "Signal Vehicle of netId %s started %s bodycams within %sm", netId, started, signal.range)
end)

---Starts the dashcam of the vehicle a recording officer sits in.
---@param netId number Vehicle network id
---@return nil
RegisterNetEvent("hype-bodycam:server:dashcam", function(netId)
    local src = source
    Debug("info", "dashcam request from %s for netId %s", src, netId)
    if not streams[bodyId(src)] then return Debug("error", "dashcam request denied: %s is not recording", src) end

    local vehicle = validVehicle(src, netId)
    if vehicle == 0 then return end

    startDashcam(src, tonumber(netId))
end)

---Tells a client whether it may open the viewer, and subscribes it to list updates.
---@param source number Player server id
---@return table<string, Stream>|false streams Current stream list, false when denied
lib.callback.register("hype-bodycam:server:access", function(source)
    local allowed = canView(source) and atTerminal(source)
    Debug(allowed and "success" or "error", "viewer access check for %s: %s", source, allowed)
    if not allowed then return false end

    subscribers[source] = true
    return streams
end)

---Tells a client whether it holds the ace that bypasses the group check, so the
---terminal option can be shown to it without a job.
---@param source number Player server id
---@return boolean allowed
lib.callback.register("hype-bodycam:server:ace", function(source)
    return Config.ViewAccess.ace and IsPlayerAceAllowed(source, Config.ViewAccess.ace) or false
end)

---Grants a viewer access to a stream and widens their culling radius so the target
---streams in for them.
---@param source number Player server id
---@param id string Stream id
---@return boolean success
---@return vector3|string result Target position on success, error key otherwise
lib.callback.register("hype-bodycam:server:view", function(source, id)
    Debug("info", "%s requested stream %s", source, tostring(id))

    local stream = type(id) == "string" and streams[id]
    if not stream then
        Debug("error", "view denied for %s: stream %s does not exist", source, tostring(id))
        return false, "offline"
    end
    if not canView(source) then
        suspicious(source, "unauthorized bodycam access: %s", id)
        return false, "no_access"
    end
    if not atTerminal(source) then
        suspicious(source, "bodycam access away from a terminal: %s", id)
        return false, "no_access"
    end
    if stream.type == "body" and stream.owner == source and not Config.Debug then
        Debug("warning", "view denied for %s: that is their own bodycam", source)
        return false, "self"
    end
    if GetPlayerRoutingBucket(source) ~= GetPlayerRoutingBucket(stream.owner) then
        Debug("warning", "view denied for %s: routing bucket %s does not match %s of the owner",
            source, GetPlayerRoutingBucket(source), GetPlayerRoutingBucket(stream.owner))
        return false, "offline"
    end

    local coords = streamCoords(stream)
    if not coords then
        Debug("error", "view denied for %s: stream %s has no position", source, id)
        return false, "offline"
    end

    viewers[source] = id
    local radius = #(GetEntityCoords(GetPlayerPed(source)) - coords) + Config.CullingPadding
    SetPlayerCullingRadius(source, radius)

    Debug("success", "%s is watching stream %s at %s, culling radius %.1fm", source, id, coords, radius)
    return true, coords
end)

---Releases a viewer slot and restores the default culling radius.
---@param source number Player server id
---@return nil
local function leave(source)
    if not viewers[source] then return end
    Debug("info", "%s stopped watching stream %s, culling radius reset", source, viewers[source])
    viewers[source] = nil
    SetPlayerCullingRadius(source, 0.0)
end

---Client closed the viewer.
---@return nil
RegisterNetEvent("hype-bodycam:server:leave", function()
    leave(source)
end)

---Unsubscribes a player from list updates and releases their viewer slot.
---@param source number Player server id
---@return nil
local function close(source)
    subscribers[source] = nil
    leave(source)
end

---Client closed the stream list.
---@return nil
RegisterNetEvent("hype-bodycam:server:close", function()
    close(source)
end)

---Cleans up viewer slots, streams and cooldowns of a player who disconnected.
---@return nil
AddEventHandler("playerDropped", function()
    local src = source
    Debug("info", "%s dropped, cleaning up", src)
    close(src)
    stopBodycam(src, "dropped")
    lastToggle[src], lastSignal[src] = nil, nil
end)

---Clears culling radii when the resource stops.
---@param resource string Name of the stopping resource
---@return nil
AddEventHandler("onResourceStop", function(resource)
    if resource ~= scriptName then return end

    local count = 0
    for viewer in pairs(viewers) do
        SetPlayerCullingRadius(viewer, 0.0)
        count = count + 1
    end

    Debug("info", "the resource is stopping: %s viewers reset", count)
end)

---Validation loop, once per TICK. Bodycams are checked every VALIDATE_EVERY ticks for
---a lost item, lost duty or a job change, and get their reminder beep. Dashcams stop
---once the vehicle is gone, or no recording officer is aboard and the lights are off,
---and otherwise follow their lights and their owner. Viewers get a refreshed culling
---radius and the current target position. Every SUMMARY_EVERY ticks a summary of the
---active streams and viewers is logged.
---@return nil
CreateThread(function()
    publish()
    Debug("info", "validation loop started: tick %sms, validate every %s ticks, summary every %s ticks",
        TICK, VALIDATE_EVERY, SUMMARY_EVERY)

    local tick = 0
    while true do
        Wait(TICK)
        tick = tick + 1
        local now = os.time()

        for id, stream in pairs(streams) do
            if stream.type == "body" then
                if tick % VALIDATE_EVERY == 0 and not canWear(stream.owner) then
                    Debug("warning", "bodycam %s of %s is no longer valid", id, stream.owner)
                    stopBodycam(stream.owner, "invalid")
                    notify(stream.owner, locale("notify.body_lost"), "error")

                elseif Config.Beep.interval > 0 and lastBeep[id] and now - lastBeep[id] >= Config.Beep.interval then
                    lastBeep[id] = now
                    Debug("info", "reminder beep due for %s", id)
                    beep(stream.owner, "reminder")
                end
            end
        end

        local changed = false
        for id, stream in pairs(streams) do
            if stream.type == "dash" then
                local vehicle = NetworkGetEntityFromNetworkId(stream.netId)

                if vehicle == 0 or not DoesEntityExist(vehicle) then
                    Debug("warning", "dashcam %s: the vehicle no longer exists", id)
                    stopStream(id, "vehicle")
                elseif GetVehicleEngineHealth(vehicle) <= -3999.0 then
                    Debug("warning", "dashcam %s: the vehicle is destroyed", id)
                    stopStream(id, "vehicle")
                else
                    local lights = IsVehicleSirenOn(vehicle)
                    local inside = officerInside(vehicle, stream.owner)

                    if not inside and not lights then
                        Debug("info", "dashcam %s: nobody aboard and the lights are off", id)
                        stopStream(id, "lights")
                    else
                        if lights ~= stream.lights then
                            Debug("info", "dashcam %s: lights changed to %s", id, lights)
                            stream.lights = lights
                            changed = true
                        end
                        if inside and inside ~= stream.owner then
                            Debug("info", "dashcam %s: owner changed from %s to %s", id, stream.owner, inside)
                            stream.owner = inside
                            stream.name, stream.callsign, stream.job = officerInfo(inside)
                            changed = true
                        end
                    end
                end
            end
        end
        if changed then publish() end

        for subscriber in pairs(subscribers) do
            if not atTerminal(subscriber) then
                Debug("warning", "%s left the terminal, closing their viewer", subscriber)
                close(subscriber)
            end
        end

        for viewer, id in pairs(viewers) do
            local stream = streams[id]
            local coords = stream and streamCoords(stream)
            local ped = GetPlayerPed(viewer)

            if coords and ped ~= 0 then
                SetPlayerCullingRadius(viewer, #(GetEntityCoords(ped) - coords) + Config.CullingPadding)
                TriggerClientEvent("hype-bodycam:client:coords", viewer, coords)
            else
                Debug("warning", "viewer %s has no position for stream %s this tick", viewer, id)
            end
        end

        if tick % SUMMARY_EVERY == 0 then
            for id, stream in pairs(streams) do
                Debug("info", "active %s stream %s: owner %s (%s), serial %s, trigger %s, %ss running",
                    stream.type, id, stream.name, stream.owner, stream.serial, stream.trigger, now - (stream.startedAt or now))
            end
            for viewer, id in pairs(viewers) do
                Debug("info", "active viewer %s on stream %s", viewer, id)
            end
        end
    end
end)

---Reports whether a player's bodycam is recording.
---@param source number Player server id
---@return boolean recording
exports("IsBodycamActive", function(source)
    local active = streams[bodyId(source)] ~= nil
    Debug("info", "export IsBodycamActive(%s): %s", source, active)
    return active
end)

---Switches a player's bodycam on or off from another resource.
---@param source number Player server id
---@param active boolean True to start recording, false to stop
---@return boolean success False when the player may not record or is already recording
exports("SetBodycam", function(source, active)
    Debug("info", "export SetBodycam(%s, %s) called", source, active)

    if active then
        if streams[bodyId(source)] then
            Debug("warning", "export SetBodycam refused: %s is already recording", source)
            return false
        end
        if not canWear(source) then
            Debug("error", "export SetBodycam refused: %s may not record", source)
            return false
        end
        startBodycam(source, "manual")
    else
        stopBodycam(source, "export")
    end
    return true
end)

---Returns every active stream, keyed by stream id.
---@return table<string, Stream> streams
exports("GetStreams", function()
    Debug("info", "export GetStreams called")
    return streams
end)

---Lists the viewers of one stream, or of all streams.
---@param id string? Stream id, nil for every viewer
---@return number[] viewers Player server ids
exports("GetViewers", function(id)
    local list = {}
    for source, watching in pairs(viewers) do
        if not id or watching == id then list[#list + 1] = source end
    end

    Debug("info", "export GetViewers(%s): %s viewers", id or "all", #list)
    return list
end)
