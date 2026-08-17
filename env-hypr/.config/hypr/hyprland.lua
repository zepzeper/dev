-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/
-- Since Hyprland 0.55 hyprlang (.conf) is deprecated in favor of lua.

-- Hyprland only adds the config dir to `package.path` *after* this file has
-- finished executing, so `require` would fail for our own modules here.
-- Resolve the directory of this file and prepend it ourselves.
local here = (debug.getinfo(1, "S").source or ""):match("^@(.*[/\\])")
    or ((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/")

local prefix = here .. "?.lua;" .. here .. "?/init.lua;"
if not package.path:find(prefix, 1, true) then
    package.path = prefix .. package.path
end

-- Order matters: window rules are evaluated top to bottom, last match wins.
require("autostart")
require("app")
require("bindings")
require("envs")
require("input")
require("looknfeel")
require("monitors")
require("rules")
