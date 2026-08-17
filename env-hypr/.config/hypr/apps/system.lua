-- Floating windows
hl.window_rule({
    match  = { tag = "floating-window" },
    float  = true,
    center = true,
    size   = { 875, 600 },
})

hl.window_rule({
    match = { class = "(zepzeper.bluetui|zepzeper.impala|zepzeper.wiremix|zepzeper.btop|zepzeper.terminal|zepzeper.bash|org.gnome.Nautilus|com.gabm.satty|About|TUI.float|imv|mpv)" },
    tag   = "+floating-window",
})

hl.window_rule({
    match = {
        class = "(xdg-desktop-portal-gtk|sublime_text|DesktopEditors|org.gnome.Nautilus)",
        title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
    },
    tag = "+floating-window",
})

hl.window_rule({ match = { class = "zepzeper.gnome.Calculator" }, float = true })

-- No transparency on media windows
hl.window_rule({
    match   = { class = "^(zoom|vlc|mpv|zepzeper.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$" },
    tag     = "-default-opacity",
    opacity = "1 1",
})

-- Popped window rounding
hl.window_rule({ match = { tag = "pop" }, rounding = 8 })

-- Prevent idle while open
hl.window_rule({ match = { tag = "noidle" }, idle_inhibit = "always" })
