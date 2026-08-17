-- See https://wiki.hypr.land/Configuring/Basics/Binds/
--
-- The old `bindd` description field is now the `description` bind flag.

local terminal = "uwsm app -- ghostty"
local browser  = "uwsm app -- helium --new-window --ozone-platform=wayland"

-- Application bindings
hl.bind("SUPER + SHIFT + Delete", hl.dsp.exec_cmd(terminal),                              { description = "Terminal" })
hl.bind("SUPER + SHIFT + F",      hl.dsp.exec_cmd("uwsm app -- nautilus --new-window"),   { description = "File manager" })
hl.bind("SUPER + SHIFT + B",      hl.dsp.exec_cmd(browser .. ' "https://home.krugten.org"'), { description = "Browser" })
hl.bind("SUPER + SHIFT + M",      hl.dsp.exec_cmd("launch-or-focus spotify"),             { description = "Music" })
hl.bind("SUPER + SHIFT + T",      hl.dsp.exec_cmd("launch-tui btop"),                     { description = "Activity" })

-- exec rules replace the old `[float; size 1600 800]` prefix
hl.bind("SUPER + SHIFT + O",
    hl.dsp.exec_cmd("launch-tui $HOME/.local/bin/llm.sh", { float = true, size = { 1600, 800 } }),
    { description = "LLM" })

-- Unlike hyprlang, `#` in a lua string is not a comment, so URLs need no escaping.
hl.bind("SUPER + SHIFT + G", hl.dsp.exec_cmd('launch-webapp "https://github.com/zepzeper"'), { description = "Github" })
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd('launch-webapp "https://app.slack.com/client/T081WNW9VAT/C0A2LHLRZCH"'), { description = "Slack" })
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd('launch-webapp "https://web.whatsapp.com/"'),   { description = "Whatsapp" })
hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd('launch-webapp "https://excalidraw.com/"'),     { description = "Draw" })
hl.bind("SUPER + SHIFT + X", hl.dsp.exec_cmd('launch-webapp "https://x.com/"'),              { description = "X" })
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd('launch-webapp "https://mastodon.social/home/"'), { description = "Mastodon" })
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd('launch-webapp "https://reddit.com/"'),         { description = "Reddit" })

hl.bind("SUPER + B",         hl.dsp.exec_cmd("launch-tui bluetui"),  { description = "Bluetooth" })
hl.bind("SUPER + BackSpace", hl.dsp.exec_cmd("launch-menu apps"),    { description = "Apps" })
hl.bind("SUPER + Delete",    hl.dsp.exec_cmd("fsearch"),             { description = "BSearch" })

-- Toggle nightlight
hl.bind("ALT + N", hl.dsp.exec_cmd("launch-nightlight"),        { description = "Toggle nightlight" })
hl.bind("ALT + S", hl.dsp.exec_cmd("launch-workspace-toggle"),  { description = "Toggle workspace layout" })

-- Captures
hl.bind("SHIFT + CTRL + P", hl.dsp.exec_cmd("launch-screenshot smart copy"), { description = "Screenshot to clipboard" })
hl.bind("SHIFT + CTRL + R", hl.dsp.exec_cmd("launch-menu screenrecord"),     { description = "Record to Videos" })

-- File sharing
hl.bind("SHIFT + CTRL + S", hl.dsp.exec_cmd("launch-menu localsend"), { description = "Share" })

-- Lock screen (hyprlock config lives in hyprlock.conf, still hyprlang)
hl.bind("SUPER + CTRL + L", hl.dsp.exec_cmd("uwsm app -- hyprlock"), { description = "Lock screen" })

require("bindings.clipboard")
require("bindings.tiling")
