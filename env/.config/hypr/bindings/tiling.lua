-- Close windows
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close window" })

-- Control tiling
-- hl.bind("SUPER + J", hl.dsp.layout("togglesplit"), { description = "Toggle window split" }) -- dwindle
hl.bind("SUPER + P",        hl.dsp.window.pseudo(),                                     { description = "Pseudo window" })
hl.bind("SUPER + T",        hl.dsp.window.float(),                                      { description = "Toggle window floating/tiling" })
hl.bind("SUPER + F",        hl.dsp.window.fullscreen({ mode = "fullscreen" }),           { description = "Full screen" })
hl.bind("SUPER + CTRL + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 2 }), { description = "Tiled full screen" })
hl.bind("SUPER + ALT + F",  hl.dsp.window.fullscreen({ mode = "maximized" }),            { description = "Full width" })
hl.bind("SUPER + O",        hl.dsp.exec_cmd("launch-window-pop"),                        { description = "Pop window out (float & pin)" })

-- Swap active window with the one next to it
hl.bind("SUPER + SHIFT + H", hl.dsp.window.swap({ direction = "l" }), { description = "Swap window to the left" })
hl.bind("SUPER + SHIFT + L", hl.dsp.window.swap({ direction = "r" }), { description = "Swap window to the right" })
hl.bind("SUPER + SHIFT + K", hl.dsp.window.swap({ direction = "u" }), { description = "Swap window up" })
hl.bind("SUPER + SHIFT + J", hl.dsp.window.swap({ direction = "d" }), { description = "Swap window down" })

-- Resize active window
hl.bind("ALT + H", hl.dsp.window.resize({ x = -100, y = 0,    relative = true }), { description = "Expand window left" })
hl.bind("ALT + L", hl.dsp.window.resize({ x = 100,  y = 0,    relative = true }), { description = "Shrink window left" })
hl.bind("ALT + K", hl.dsp.window.resize({ x = 0,    y = -100, relative = true }), { description = "Shrink window up" })
hl.bind("ALT + J", hl.dsp.window.resize({ x = 0,    y = 100,  relative = true }), { description = "Expand window down" })

-- Move focus
hl.bind("SUPER + H", hl.dsp.focus({ direction = "l" }), { description = "Move window focus left" })
hl.bind("SUPER + L", hl.dsp.focus({ direction = "r" }), { description = "Move window focus right" })
hl.bind("SUPER + K", hl.dsp.focus({ direction = "u" }), { description = "Move window focus up" })
hl.bind("SUPER + J", hl.dsp.focus({ direction = "d" }), { description = "Move window focus down" })

-- Move active window to workspace LEFT OR RIGHT
hl.bind("ALT + SHIFT + H", hl.dsp.window.move({ workspace = "-1" }), { description = "Move window to workspace left" })
hl.bind("ALT + SHIFT + L", hl.dsp.window.move({ workspace = "+1" }), { description = "Move window to workspace right" })

-- Workspaces are bound by keycode so they follow the physical 1-9,0 row.
-- code:10 is `1`, code:19 is `0`.
for i = 1, 10 do
    local key = "code:" .. (i + 9)

    -- Switch workspaces with SUPER + [1-9; 0]
    hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = i }),
        { description = "Switch to workspace " .. i })

    -- Move active window to a workspace with SUPER + SHIFT + [1-9; 0]
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }),
        { description = "Move window to workspace " .. i })

    -- Move active window silently with SUPER + SHIFT + ALT + [1-9; 0]
    hl.bind("SUPER + SHIFT + ALT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }),
        { description = "Move window silently to workspace " .. i })
end

-- Window movement
hl.bind("ALT + mouse:272",   hl.dsp.window.drag(),   { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Manage floating
hl.bind("SUPER + E",         hl.dsp.window.cycle_next({ floating = true }))
hl.bind("SUPER + SHIFT + E", hl.dsp.window.cycle_next({ tiled = true }))
