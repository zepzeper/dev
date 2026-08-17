-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
--
-- The old `exec =` ran on startup *and* on every config reload. `hyprland.start`
-- only fires once, so we also hook `config.reloaded` to keep that behavior.
-- The `pkill` prefix makes these idempotent if both ever fire.

local function autostart()
    hl.exec_cmd("pkill waybar; uwsm-app -- waybar")
    hl.exec_cmd("pkill mako; uwsm-app -- mako")
    hl.exec_cmd("pkill hyprpaper; uwsm-app -- hyprpaper")

    -- hl.exec_cmd("uwsm-app -- hypridle")
    -- hl.exec_cmd("uwsm-app -- fcitx5")
    -- hl.exec_cmd("uwsm-app -- swayosd-server")
end

hl.on("hyprland.start", autostart)
hl.on("config.reloaded", autostart)
