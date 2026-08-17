-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
--
-- Note: hl.env() does not go through a shell, so `$HOME` / `~` would be passed
-- through literally. We expand them in lua instead.
local home = os.getenv("HOME")

-- Cursor
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")

hl.config({
    cursor = {
        no_hardware_cursors = true,
    },
})

-- Force all apps to use Wayland
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("SDL_VIDEODRIVER", "wayland,x11")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Allow better support for screen sharing (Google Meet, Discord, etc)
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})

-- Use XCompose file
hl.env("XCOMPOSEFILE", home .. "/.XCompose")

-- Don't show update news on first launch
hl.config({
    ecosystem = {
        no_update_news = true,
    },
})

-- NVIDIA
hl.env("NVD_BACKEND", "direct")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")

hl.env("SCREENSHOT_DIR", home .. "/Pictures/Screenshots")
hl.env("SCREENRECORD_DIR", home .. "/Videos/Recordings")
