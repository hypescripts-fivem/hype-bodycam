local Config <const> = require "config.config"

local streams = {} ---@type table<string, table> Stream list last sent by the server, only while the viewer is open

---@type table<string, number> Control ids used while viewing a stream
local Keys <const> = {
    prev = 44,
    next = 38,
    prevAlt = 174,
    nextAlt = 175,
    camera = 37,
    back = 194,
    exit = 200,
    copy = 26,
}

local menuOpen = false
local viewing = nil ---@type table? Stream being watched, a copy of the stream list entry
local cam = nil ---@type number? Scripted camera handle
local switching = false
local signalLost = false
local ended = false
local terminalCoords = nil ---@type vector3? Terminal the viewer was opened from
local radarWasHidden = false
local lastHudKey = nil ---@type string? Last hud payload sent to the NUI, encoded as json

---@type { entity: number, coords: vector3?, since: number, offset: vector3? } Ped or vehicle being watched
local target = { entity = 0, coords = nil, since = 0, offset = nil }
local camIndex = 1 ---@type 1|2 Fleet camera in use: 1 = front, 2 = cabin
local modelNames = {} ---@type table<number, string> Vehicle model hash to display label

Debug("info", "bodycam viewer loaded: %s terminals, filter=%s, loadTimeout=%sms, switchDelay=%sms",
    #Config.Terminals, Config.Filter and Config.Filter.timecycle or "off", Config.LoadTimeout, Config.SwitchDelay)

---Shows a notification under the resource title, through the notify module, so the
---resource configured in Config.Notifications is used.
---@param description string Text to display
---@param notifyType string? Notification type, defaults to "inform"
---@return nil
local function notify(description, notifyType)
    Debug("info", "notify (%s): %s", notifyType or "inform", description)
    Modules.Client.Notify.SendNotify(locale("title"), description, 5000, notifyType or "inform")
end

---Rounds a number to a fixed number of decimals.
---@param value number Value to round
---@param decimals number? Decimal places, defaults to 0
---@return number rounded
local function round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

---Resolves a vehicle model hash to its display label, cached per model.
---@param model number? Vehicle model hash
---@return string? label Nil when no model was given
local function modelLabel(model)
    if not model then return nil end
    if modelNames[model] then return modelNames[model] end

    local name = GetDisplayNameFromVehicleModel(model)
    local label = GetLabelText(name)
    if label == "NULL" then label = name end

    modelNames[model] = label
    Debug("info", "model %s resolved to label %s", model, label)
    return label
end

---Flattens the stream map into a stable order: bodycams first, then by start time.
---@param source table<string, table>? Stream map, defaults to the last received list
---@return table[] streams Sorted stream list
local function sortedStreams(source)
    local list = {}
    for _, stream in pairs(source or streams) do list[#list + 1] = stream end

    table.sort(list, function(a, b)
        if a.type ~= b.type then return a.type == "body" end
        if a.startedAt ~= b.startedAt then return a.startedAt < b.startedAt end
        return a.id < b.id
    end)
    return list
end

---Builds the NUI payload for one stream.
---@param stream table Stream entry
---@param index number Position in the sorted list
---@param total number Number of streams in the list
---@return table payload
local function streamPayload(stream, index, total)
    return {
        id = stream.id,
        type = stream.type,
        name = stream.name,
        callsign = stream.callsign,
        job = stream.job,
        grade = stream.grade,
        serial = stream.serial,
        trigger = stream.trigger,
        plate = stream.plate,
        vehicle = modelLabel(stream.model),
        lights = stream.lights,
        elapsed = math.max(0, GetCloudTimeAsInt() - (stream.startedAt or 0)),
        self = stream.owner == cache.serverId,
        index = index,
        total = total,
    }
end

---Builds the NUI payload for the whole stream list.
---@param source table<string, table>? Stream map, defaults to the last received list
---@return table[] payload NUI payload per stream
---@return table[] streams Sorted stream list behind the payloads
local function streamList(source)
    local list = sortedStreams(source)
    local payload = {}
    for index, stream in ipairs(list) do payload[index] = streamPayload(stream, index, #list) end
    Debug("info", "stream list built: %s streams", #list)
    return payload, list
end

---Looks up a stream by id and reports its position in the sorted list.
---@param id string? Stream id
---@param source table<string, table>? Stream map, defaults to the last received list
---@return table? stream
---@return number? index
---@return number? total
local function findStream(id, source)
    local list = sortedStreams(source)
    for index, stream in ipairs(list) do
        if stream.id == id then return stream, index, #list end
    end

    Debug("warning", "stream %s was not found among %s streams", id or "nil", #list)
end

---Resolves the local entity a stream is attached to.
---@param stream table Stream entry
---@return number entity Entity handle, 0 when it has not streamed in yet
local function resolveEntity(stream)
    if stream.type == "body" then
        local player = GetPlayerFromServerId(stream.owner)
        if player == -1 then return 0 end

        local ped = GetPlayerPed(player)
        return DoesEntityExist(ped) and ped or 0
    end

    if not NetworkDoesEntityExistWithNetworkId(stream.netId) then return 0 end
    local vehicle = NetToVeh(stream.netId)
    return DoesEntityExist(vehicle) and vehicle or 0
end

---Mount position behind the windscreen, at rear-view mirror height, relative to the vehicle.
---Falls back to the configured default offset when the bone is missing.
---@param vehicle number Vehicle entity handle
---@return vector3 offset
local function dashOffset(vehicle)
    local dashcam = Config.Dashcam
    local model = GetEntityModel(vehicle)
    if dashcam.vehicles[model] then
        Debug("info", "dashcam offset for model %s taken from the config: %s", model, dashcam.vehicles[model])
        return dashcam.vehicles[model]
    end

    local bone = GetEntityBoneIndexByName(vehicle, "windscreen")
    if bone ~= -1 then
        local world = GetWorldPositionOfEntityBone(vehicle, bone)
        local offset = GetOffsetFromEntityGivenWorldCoords(vehicle, world.x, world.y, world.z)
        local mount = vec3(0.0, offset.y - dashcam.windscreenBack, offset.z + dashcam.windscreenUp)
        Debug("info", "dashcam offset for model %s taken from the windscreen bone: %s", model, mount)
        return mount
    end

    Debug("warning", "model %s has no windscreen bone, using defaultOffset %s", model, dashcam.defaultOffset)
    return dashcam.defaultOffset
end

---Creates or re-attaches the scripted camera to the target entity with the bodycam,
---dashcam or cabin settings. The cabin camera shares the dashcam mount and faces
---the rear seats.
---@param stream table Stream entry
---@param entity number Entity to attach the camera to
---@return nil
local function attachCamera(stream, entity)
    local settings, heading = Config.Bodycam, 0.0
    local offset = Config.Bodycam.offset

    if stream.type == "dash" then
        settings = Config.Dashcam
        offset = dashOffset(entity)
        target.offset = offset

        if camIndex == 2 then
            settings, heading = Config.Dashcam.cabin, 180.0
            offset = offset + settings.offset
        end
    end

    if not cam then
        cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        RenderScriptCams(true, false, 0, true, true)
        Debug("info", "scripted camera %s created", cam)
    end

    DetachCam(cam)
    SetCamFov(cam, settings.fov)
    SetCamNearClip(cam, 0.05)
    HardAttachCamToEntity(cam, entity, settings.pitch, 0.0, heading, offset.x, offset.y, offset.z, true)
    SetFocusEntity(entity)

    Debug("success", "camera attached to entity %s for %s stream %s: cam %s, offset %s, pitch %s, fov %s, heading %s",
        entity, stream.type, stream.id, camIndex, offset, settings.pitch, settings.fov, heading)
end

---Follows the target: attaches the camera once it streams in, and focuses its last
---known position while it is gone.
---@return boolean loaded True while the target entity exists locally
local function trackTarget()
    local entity = resolveEntity(viewing)

    if entity ~= target.entity then
        Debug("info", "target entity changed from %s to %s after %sms", target.entity, entity, GetGameTimer() - target.since)
        target.entity = entity
        if entity ~= 0 then
            attachCamera(viewing, entity)
        elseif target.coords then
            local c = target.coords
            Debug("warning", "target of stream %s unloaded, holding focus at %s", viewing.id, c)
            SetFocusPosAndVel(c.x, c.y, c.z, 0.0, 0.0, 0.0)
        end
    end

    return entity ~= 0
end

---Applies the configured timecycle modifier to the camera feed.
---@return nil
local function applyFilter()
    local filter = Config.Filter
    if not filter or not filter.timecycle then return Debug("info", "no picture filter configured") end

    SetTimecycleModifier(filter.timecycle)
    SetTimecycleModifierStrength(filter.strength or 1.0)
    Debug("info", "filter %s applied at strength %s", filter.timecycle, filter.strength or 1.0)
end

---Toggles the "no signal" overlay, sending nothing when the state is unchanged.
---@param lost boolean True when the target is not loaded
---@return nil
local function setSignal(lost)
    if lost == signalLost then return end
    signalLost = lost
    Debug(lost and "warning" or "success", "signal %s for stream %s", lost and "lost" or "restored", viewing and viewing.id or "-")
    SendNUIMessage({ action = "nui/signal", payload = { lost = lost } })
end

local speedFactor <const> = Config.UI.speedUnit == "mph" and 2.236936 or 3.6

---Pushes heading, street, zone, coordinates and vehicle telemetry to the hud overlay.
---Nothing is sent when the payload is unchanged.
---@return nil
local function sendHud()
    local entity = target.entity
    if entity == 0 then return end

    local coords = GetEntityCoords(entity)
    local street, crossing = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local vehicle = viewing.type == "dash" and entity or GetVehiclePedIsIn(entity, false)

    local hud = {
        heading = round((360.0 - GetEntityHeading(entity)) % 360.0, 0),
        street = GetStreetNameFromHashKey(street),
        crossing = crossing ~= 0 and GetStreetNameFromHashKey(crossing) or nil,
        zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z)),
        lat = round(coords.y, 1),
        lon = round(coords.x, 1),
        cam = camIndex,
    }

    if vehicle ~= 0 then
        hud.speed = round(GetEntitySpeed(vehicle) * speedFactor, 0)
        hud.lights = IsVehicleSirenOn(vehicle)
        hud.siren = hud.lights and IsVehicleSirenAudioOn(vehicle)
    end

    local key = json.encode(hud)
    if key == lastHudKey then return end

    lastHudKey = key
    SendNUIMessage({ action = "nui/hud", payload = hud })
end

---Debug helper: copies the current dashcam offset as a Config.Dashcam.vehicles entry.
---@return nil
local function copyOffset()
    if not viewing or viewing.type ~= "dash" or target.entity == 0 then
        return Debug("warning", "offset copy skipped: no loaded dashcam stream on screen")
    end

    local text = ("[`%s`] = vec3(%.3f, %.3f, %.3f),"):format(GetDisplayNameFromVehicleModel(GetEntityModel(target.entity)):lower(),
        target.offset.x, target.offset.y, target.offset.z)

    lib.setClipboard(text)
    print(text)
    Debug("success", "offset copied to the clipboard: %s", text)
    notify(locale("notify.copied"), "success")
end

---Checks whether a given stream is the one on screen.
---@param id string Stream id
---@return boolean viewing
local function isViewing(id)
    return viewing ~= nil and viewing.id == id
end

---Tears down the camera, restores hud, radar and player state, and releases the
---server-side viewer slot.
---@return nil
local function exitCamera()
    if not viewing then return end
    Debug("info", "leaving stream %s after %sms", viewing.id, GetGameTimer() - target.since)

    viewing = nil
    signalLost, ended = false, false
    target = { entity = 0, coords = nil, since = 0, offset = nil }

    if cam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(cam, false)
        Debug("info", "scripted camera %s destroyed", cam)
        cam = nil
    end

    ClearFocus()
    ClearTimecycleModifier()
    FreezeEntityPosition(cache.ped, false)
    if not radarWasHidden then DisplayRadar(true) end

    Debug("success", "camera state restored, releasing the viewer slot")
    TriggerServerEvent("hype-bodycam:server:leave")
end

local startViewLoop
local switchFleetCamera

---Closes the viewer completely: camera, menu and NUI focus.
---@return nil
function CloseBodycams()
    if not menuOpen and not viewing then return end
    Debug("info", "closing the viewer (menu open: %s, watching: %s)", menuOpen, viewing and viewing.id or "-")

    exitCamera()
    menuOpen = false
    terminalCoords = nil
    TriggerServerEvent("hype-bodycam:server:close")

    SetNuiFocus(false, false)
    SendNUIMessage({ action = "nui/hide" })
    Debug("success", "viewer closed")
end

---Leaves the current stream and returns to the stream list.
---@return nil
local function backToMenu()
    Debug("info", "returning to the stream list")
    exitCamera()
    menuOpen = true

    SendNUIMessage({ action = "nui/menu", payload = { streams = streamList() } })
    SetNuiFocus(true, true)
end

---Connects to a stream: asks the server for access, moves focus to the target area,
---waits for it to stream in, then shows the feed. The viewer is frozen on the first
---connect, because the ground beneath them can unload once focus moves away.
---@param id string? Stream id
---@return boolean success
---@return string? error One of "offline", "busy", "cancelled", "self", "no_access"
local function connect(id)
    Debug("info", "connecting to stream %s", id or "nil")

    local stream, index, total = findStream(id)
    if not stream then
        Debug("error", "connect failed: stream %s is offline", id or "nil")
        return false, "offline"
    end
    if switching then
        Debug("warning", "connect refused: another switch is still running")
        return false, "busy"
    end

    switching = true
    local ok, result = lib.callback.await("hype-bodycam:server:view", false, id)
    Debug("info", "server answered the view request for %s: ok=%s, result=%s", id, ok, result)

    if not ok or (not menuOpen and not viewing) then
        switching = false
        if ok then
            Debug("warning", "connect cancelled after the server granted access, releasing the slot")
            TriggerServerEvent("hype-bodycam:server:leave")
        end
        return false, ok and "cancelled" or result or "offline"
    end

    local first = not viewing
    viewing = stream
    signalLost, ended = false, false
    lastHudKey = nil
    camIndex = 1
    target = { entity = 0, coords = result, since = GetGameTimer(), offset = nil }

    SendNUIMessage({ action = "nui/connecting", payload = streamPayload(stream, index, total) })
    PlaySoundFrontend(-1, "Change_Cam", "MP_CCTV_SOUNDSET", true)
    Debug("info", "connecting to %s stream %s of %s (%s/%s), first connect: %s",
        stream.type, stream.id, stream.name, index, total, first)

    if first then
        menuOpen = false
        SetNuiFocus(false, false)
        radarWasHidden = IsRadarHidden()
        DisplayRadar(false)
        applyFilter()
        FreezeEntityPosition(cache.ped, true)
        Debug("info", "viewer frozen, radar hidden (was already hidden: %s)", radarWasHidden)
    end

    local started = GetGameTimer()
    SetFocusPosAndVel(result.x, result.y, result.z, 0.0, 0.0, 0.0)
    if not cam then
        cam = CreateCamWithParams("DEFAULT_SCRIPTED_CAMERA", result.x, result.y, result.z + 1.0, 0.0, 0.0, 0.0, 70.0, true, 2)
        RenderScriptCams(true, false, 0, true, true)
        Debug("info", "placeholder camera %s created at %s", cam, result)
    else
        DetachCam(cam)
        SetCamCoord(cam, result.x, result.y, result.z + 1.0)
        Debug("info", "camera %s moved to %s", cam, result)
    end

    if first then startViewLoop() end

    local timeout = started + Config.LoadTimeout
    while isViewing(id) and not trackTarget() and GetGameTimer() < timeout do Wait(50) end
    Debug("info", "target of %s loaded in %sms: %s", id, GetGameTimer() - started, target.entity ~= 0)

    local remaining = Config.SwitchDelay - (GetGameTimer() - started)
    if remaining > 0 then
        Debug("info", "holding static for another %sms", remaining)
        Wait(remaining)
    end

    switching = false
    if not isViewing(id) then
        Debug("warning", "connect to %s was cancelled while loading", id)
        return false, "cancelled"
    end

    SendNUIMessage({ action = "nui/view", payload = streamPayload(stream, index, total) })
    if target.entity == 0 then
        Debug("warning", "stream %s is on screen without a loaded target, showing no signal", id)
        setSignal(true)
    else
        Debug("success", "stream %s is live on entity %s", id, target.entity)
    end
    return true
end

---Switches to the next or previous stream, skipping the viewer's own bodycam.
---@param direction 1|-1 1 = next, -1 = previous
---@return nil
local function cycle(direction)
    local list = sortedStreams()
    local count = #list
    if count < 2 then return Debug("info", "cycle skipped: only %s stream available", count) end

    local current = 1
    for index, stream in ipairs(list) do
        if stream.id == viewing.id then current = index break end
    end
    Debug("info", "cycling %s from position %s of %s", direction == 1 and "forward" or "backward", current, count)

    for step = 1, count - 1 do
        local stream = list[(current - 1 + direction * step) % count + 1]
        if stream.owner ~= cache.serverId or stream.type ~= "body" or Config.Debug then
            CreateThread(function()
                local ok, err = connect(stream.id)
                if not ok and err ~= "cancelled" and err ~= "busy" then notify(locale("notify." .. err), "error") end
            end)
            return
        end
        Debug("info", "cycle skipped own bodycam %s", stream.id)
    end

    Debug("warning", "cycle found no other stream to switch to")
end

---Reports whether viewing must stop: the viewer died, ragdolled, or walked away
---from the terminal.
---@return boolean abort
local function shouldAbort()
    if IsEntityDead(cache.ped) then
        Debug("warning", "aborting: the viewer died")
        return true
    end
    if IsPedRagdoll(cache.ped) then
        Debug("warning", "aborting: the viewer is ragdolling")
        return true
    end
    if terminalCoords and #(GetEntityCoords(cache.ped) - terminalCoords) > Config.TerminalDistance then
        Debug("warning", "aborting: the viewer walked more than %sm from the terminal", Config.TerminalDistance)
        return true
    end
    return false
end

---Fleet 3: toggles between the front and the cabin camera of a dashcam stream.
---@return nil
function switchFleetCamera()
    if not viewing or viewing.type ~= "dash" then return Debug("info", "camera switch skipped: no dashcam stream on screen") end
    if not Config.Dashcam.cabin.enabled then return Debug("info", "camera switch skipped: the cabin camera is disabled") end

    camIndex = camIndex == 1 and 2 or 1
    Debug("info", "switched to the %s camera of stream %s", camIndex == 1 and "front" or "cabin", viewing.id)

    PlaySoundFrontend(-1, "Change_Cam", "MP_CCTV_SOUNDSET", true)
    if target.entity ~= 0 then attachCamera(viewing, target.entity) end
    sendHud()
end

---Shows the stream-ended overlay and returns to the list after the configured delay.
---@return nil
local function onEnded()
    if not viewing or ended then return end
    ended = true

    local id = viewing.id
    Debug("warning", "stream %s ended, returning to the list in %sms", id, Config.EndedDelay)
    SendNUIMessage({ action = "nui/signal", payload = { lost = true, ended = true } })

    SetTimeout(Config.EndedDelay, function()
        if isViewing(id) and ended then backToMenu() end
    end)
end

---Starts the viewing loop: blocks controls, hides the hud, tracks the target ten
---times a second and handles the viewer keybinds.
---@return nil
function startViewLoop()
    Debug("info", "view loop started")

    CreateThread(function()
        local nextTick = 0

        while viewing do
            DisableAllControlActions(0)
            HideHudAndRadarThisFrame()

            local now = GetGameTimer()
            if now >= nextTick and not switching and not ended then
                nextTick = now + 100

                local loaded = trackTarget()
                setSignal(not loaded)
                if loaded then sendHud() end
                if shouldAbort() then CloseBodycams() end
            end

            if not viewing then break end

            if IsDisabledControlJustReleased(0, Keys.exit) then
                Debug("info", "key: exit")
                CloseBodycams()
            elseif IsDisabledControlJustReleased(0, Keys.back) then
                Debug("info", "key: back to the list")
                backToMenu()
            elseif not switching then
                if IsDisabledControlJustPressed(0, Keys.next) or IsDisabledControlJustPressed(0, Keys.nextAlt) then
                    Debug("info", "key: next stream")
                    cycle(1)
                elseif IsDisabledControlJustPressed(0, Keys.prev) or IsDisabledControlJustPressed(0, Keys.prevAlt) then
                    Debug("info", "key: previous stream")
                    cycle(-1)
                elseif IsDisabledControlJustPressed(0, Keys.camera) then
                    Debug("info", "key: switch Fleet camera")
                    switchFleetCamera()
                elseif Config.Debug and IsDisabledControlJustPressed(0, Keys.copy) then
                    Debug("info", "key: copy the dashcam offset")
                    copyOffset()
                end
            end

            Wait(0)
        end

        Debug("info", "view loop stopped")
    end)
end

---Opens the stream list after a server-side access check.
---@param fromTerminal vector3? Terminal position when opened from one, nil otherwise
---@return nil
function OpenBodycams(fromTerminal)
    if menuOpen or viewing then return Debug("info", "open skipped: the viewer is already open") end
    if IsPauseMenuActive() then return Debug("info", "open skipped: the pause menu is active") end
    if IsNuiFocused() then return Debug("info", "open skipped: another nui has focus") end

    Debug("info", "opening the viewer from %s", fromTerminal and tostring(fromTerminal) or "a command or export")

    local list = lib.callback.await("hype-bodycam:server:access", false)
    if not list then
        Debug("error", "open denied: the server refused view access")
        return notify(locale("notify.no_access"), "error")
    end

    streams = list

    terminalCoords = fromTerminal
    menuOpen = true

    SendNUIMessage({
        action = "nui/open",
        payload = {
            locales = lib.getLocales(),
            ui = Config.UI,
            debug = Config.Debug,
            streams = streamList(),
        }
    })
    SetNuiFocus(true, true)
    Debug("success", "viewer opened")
end

---NUI: closes the viewer.
---@param _ any Unused request body
---@param cb fun(response: table) NUI response callback
---@return nil
RegisterNUICallback("nui/close", function(_, cb)
    Debug("info", "nui requested a close")
    cb({ success = true })
    CloseBodycams()
end)

---NUI: connects to the stream picked in the list.
---@param data table Request body holding the stream id
---@param cb fun(response: table) NUI response callback
---@return nil
RegisterNUICallback("nui/view", function(data, cb)
    if not menuOpen then
        Debug("warning", "nui view request refused: the list is not open")
        return cb({ success = false, error = "busy" })
    end

    local ok, err = connect(type(data) == "table" and data.id or nil)
    Debug("info", "nui view request answered: success=%s, error=%s", ok, err or "-")
    cb({ success = ok, error = err })
end)

---Stores the last known target position, used to hold focus while the target is unloaded.
---@param coords vector3 Current target position
---@return nil
RegisterNetEvent("hype-bodycam:client:coords", function(coords)
    if not viewing then return end
    target.coords = coords
    if target.entity == 0 then
        Debug("info", "target position update while unloaded: %s", coords)
        SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
    end
end)

---Handles a stream the server shut down.
---@param id string Id of the stream that ended
---@return nil
RegisterNetEvent("hype-bodycam:client:ended", function(id)
    Debug("info", "the server reports stream %s as ended", id)
    if viewing and viewing.id == id then onEnded() end
end)

---Refreshes the list and the current feed when the server sends a new stream list, so a
---handover (owner or lights change) shows up in the ui right away.
---@param value table<string, table>? New stream map
---@return nil
RegisterNetEvent("hype-bodycam:client:streams", function(value)
    value = value or {}
    streams = value

    if menuOpen then
        Debug("info", "stream list changed while the list is open, refreshing the nui")
        SendNUIMessage({ action = "nui/streams", payload = { streams = streamList(value) } })
    end

    if viewing then
        local stream, index, total = findStream(viewing.id, value)
        if not stream then
            Debug("warning", "stream %s disappeared from the stream list", viewing.id)
            return onEnded()
        end

        if stream.owner ~= viewing.owner then
            Debug("info", "stream %s changed owner: %s -> %s", stream.id, viewing.owner, stream.owner)
        end
        if stream.lights ~= viewing.lights then
            Debug("info", "stream %s lights are now %s", stream.id, stream.lights)
        end

        viewing = stream
        SendNUIMessage({ action = "nui/stream", payload = streamPayload(stream, index, total) })
    end
end)

---Registers a target zone for every configured terminal, through the target module,
---so it works on both ox_target and qb-target.
---@return nil
CreateThread(function()
    Wait(500)

    if not Modules.Client.Target.AddSphereZone then
        return Debug("warning", "no supported target resource found, bodycam terminals were not created")
    end

    -- Ace holders get the option without a job; the server still checks access on open
    local ace = Config.ViewAccess.ace and lib.callback.await("hype-bodycam:server:ace", false)

    for index, terminal in ipairs(Config.Terminals) do
        local name = ("hype-bodycam:terminal:%s"):format(index)

        Modules.Client.Target.AddSphereZone(name, terminal.coords, terminal.radius or 0.8, {
            {
                name = name,
                icon = "fa-solid fa-person-rays",
                label = locale("target_label"),
                groups = not ace and Config.ViewAccess.groups or nil,
                distance = 2.0,
                onSelect = function() OpenBodycams(terminal.coords) end,
            },
        })
        Debug("info", "terminal %s registered: %s at %s", index, terminal.label or "unnamed", terminal.coords)
    end

    Debug("success", "%s bodycam terminals registered", #Config.Terminals)
end)

if Config.Command then
    RegisterCommand(Config.Command, function() OpenBodycams() end, false)
    Debug("info", "command /%s registered", Config.Command)
end

---Closes the viewer when the resource stops, so no camera or focus is left behind.
---@param resource string Name of the stopping resource
---@return nil
AddEventHandler("onResourceStop", function(resource)
    if resource ~= cache.resource then return end
    Debug("info", "the resource is stopping, closing the viewer")
    CloseBodycams()
end)

---Opens the stream list without a terminal.
---@return nil
exports("Open", function()
    Debug("info", "export Open called")
    OpenBodycams()
end)

---Closes the viewer.
---@return nil
exports("Close", function()
    Debug("info", "export Close called")
    CloseBodycams()
end)

---Reports whether the list or a stream is currently on screen.
---@return boolean open
exports("IsOpen", function()
    local open = menuOpen or viewing ~= nil
    Debug("info", "export IsOpen: %s", open)
    return open
end)

---Returns the id of the stream being watched.
---@return string? id Nil when nothing is being watched
exports("GetViewingStream", function()
    Debug("info", "export GetViewingStream: %s", viewing and viewing.id or "none")
    return viewing and viewing.id or nil
end)
