return {
    -- Dev only: lets you watch your own stream, draws ox_target zones,
    -- and copies the dashcam offset to your clipboard with [C] while viewing.
    -- Keep false on a live server.
    Debug = false,

    Item = "bodycam",

    -- Notification resource: "auto" picks okokNotify, ps-ui or ox_lib, whichever is running.
    -- Set it to one of those names to force it.
    Notifications = "auto",

    -- Device serials (Axon format: X + 8 digits, e.g. X60312274)
    -- Bodycam: assigned randomly the first time an item is created, shown in the inventory tooltip
    -- Fleet: derived from the plate, so a vehicle always reports the same serial
    Serial = {
        body = "X6031",          -- Prefix; the remaining 4 digits are random
        fleet = "X7330",
    },

    -- Who may turn a bodycam on
    Access = {
        groups = { police = 0, bcso = 0 },   -- job name -> minimum grade level
        requireDuty = true,                  -- Player must be on duty (ESX has no duty, so it is ignored there)
    },

    -- Who may watch streams
    ViewAccess = {
        groups = { police = 0, bcso = 0 },
        requireDuty = true,
        ace = "group.admin",                 -- Holders of this ace bypass the group check (false = disabled)
    },

    Command = false,             -- Command that opens the stream list (e.g. "bodycams"); false = terminals only

    -- Viewing terminals (ox_target). Walking away from the terminal closes the viewer.
    -- Defaults match the hype-camera computers, so a single PC offers both options.
    Terminals = {
        { coords = vec3(441.85, -978.92, 30.69), radius = 0.8, label = "Mission Row PD" },
        { coords = vec3(1853.18, 3689.62, 34.27), radius = 0.8, label = "Sandy Shores Sheriff" },
        { coords = vec3(-448.29, 6011.95, 31.72), radius = 0.8, label = "Paleto Bay Sheriff" },
    },
    TerminalDistance = 3.0,      -- m, viewer closes past this distance from the terminal

    -- Body-worn camera (attached to the officer's ped)
    Bodycam = {
        offset = vec3(0.0, 0.32, 0.42),      -- Position relative to the ped (x right, y forward, z up)
        pitch = -6.0,                        -- Downward tilt
        fov = 88.0,                          -- Wide angle
    },

    -- Vehicle camera
    Dashcam = {
        classes = { [18] = true },           -- Vehicle classes that get a dashcam automatically (18 = Emergency)
        models = {                           -- Extra models that always get one, whatever their class (e.g. unmarked units)
            -- `fbi`, `fbi2`,
        },
        excluded = {                         -- Models that never get one, even if their class matches
            `ambulance`, `firetruk`, `lguard`,
        },
        driverOnly = false,                  -- true = only recording when entering the driver's seat
        pitch = -3.0,
        fov = 72.0,
        -- Fleet 3 second camera: same housing as the front one, facing the rear seats.
        -- Viewers switch between them with [TAB].
        cabin = {
            enabled = true,
            offset = vec3(0.0, 0.04, -0.03),   -- Relative to the front camera position
            pitch = -16.0,
            fov = 92.0,
        },
        -- Mounted behind the windscreen; defaultOffset is the fallback when the bone is missing.
        -- Per-model override: vehicles = { [`police3`] = vec3(0.0, 0.25, 0.62) }
        defaultOffset = vec3(0.0, 0.35, 0.65),
        windscreenBack = 0.28,               -- m behind the "windscreen" bone
        windscreenUp = 0.08,                 -- ... and this far above it
        vehicles = {},
    },

    -- Server-side culling radius for the viewer: distance to the target + this padding (m).
    -- Raise it if distant streams flicker, lower it to send less entity data.
    CullingPadding = 150.0,

    LoadTimeout = 6000,          -- ms to show "connecting" while the target loads before falling back to "no signal"
    SwitchDelay = 450,           -- ms of static shown on every stream switch
    EndedDelay = 2500,           -- ms to wait after a stream ends before returning to the list

    -- Picture effect (timecycle modifier). false = disabled
    Filter = {
        timecycle = "scanline_cam_cheap",
        strength = 0.35,
    },

    -- Recording beeps (real Axon audio): double beep on start, single on stop, periodic reminder while recording.
    -- Nearby players hear them too, attenuated by distance.
    Beep = {
        enabled = true,
        interval = 120,          -- s between reminder beeps while recording (Axon default is 2 min), 0 = off
        range = 8.0,             -- m within which other players hear the beeps
        volume = 0.12,           -- 0.0 - 1.0 (the source file is loud; above 0.2 gets annoying)
    },

    -- Axon Signal: triggers that start recording automatically for on-duty officers carrying the item
    Signal = {
        sidearm = {              -- Signal Sidearm: on drawing a firearm
            enabled = true,
            excluded = { `WEAPON_STUNGUN`, `WEAPON_STUNGUN_MP`, `WEAPON_FLAREGUN`, `WEAPON_FIREEXTINGUISHER`, `WEAPON_PETROLCAN` },
        },
        vehicle = {              -- Signal Vehicle: when a dashcam vehicle's lights go on, for officers inside and nearby
            enabled = true,
            range = 10.0,        -- m (Axon: ~30 ft)
        },
    },

    UI = {
        utcOffset = false,       -- Timezone for the recording timestamp (e.g. 3 = +0300), false = the player's local clock
        locale = "en-US",        -- Date format (Intl locale tag)
        speedUnit = "kmh",       -- "kmh" | "mph"
        indicator = true,        -- Axon status indicator on the officer's screen while recording
        indicatorPosition = "top-right", -- "top-right" | "top-left" | "bottom-right" | "bottom-left"
    },
}
