hl.window_rule({
    name  = "Meet rule",
    match = { title = "^(Meet*)$" },

    float = true,
    size  = { 30, 37 },
    move  = { "(monitor_w*1)-220", "190" },
    pin   = true,
})
