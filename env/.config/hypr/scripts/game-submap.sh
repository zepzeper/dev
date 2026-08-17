#!/bin/bash

bind_alt() {
    hyprctl keyword bindd "ALT, H, Expand window left, resizeactive, -100 0"
    hyprctl keyword bindd "ALT, L, Shrink window left, resizeactive, 100 0"
    hyprctl keyword bindd "ALT, K, Shrink window up, resizeactive, 0 -100"
    hyprctl keyword bindd "ALT, J, Expand window down, resizeactive, 0 100"
    hyprctl keyword bindd "ALT SHIFT, H, Move window to workspace left, movetoworkspace, -1"
    hyprctl keyword bindd "ALT SHIFT, L, Move window to workspace right, movetoworkspace, +1"
    hyprctl keyword bindd "ALT, N, Toggle nightlight, exec, launch-nightlight"
    hyprctl keyword bindd "ALT, S, Toggle workspace layout, exec, launch-workspace-toggle"
    hyprctl keyword bindm "ALT, mouse:272, movewindow"
}

unbind_alt() {
    hyprctl keyword unbind "ALT, H"
    hyprctl keyword unbind "ALT, L"
    hyprctl keyword unbind "ALT, K"
    hyprctl keyword unbind "ALT, J"
    hyprctl keyword unbind "ALT SHIFT, H"
    hyprctl keyword unbind "ALT SHIFT, L"
    hyprctl keyword unbind "ALT, N"
    hyprctl keyword unbind "ALT, S"
    hyprctl keyword unbind "ALT, mouse:272"
}

handle() {
    local event="$1"

    if [[ "$event" == activewindow\>\>* ]]; then
        local class
        class=$(echo "$event" | cut -d'>' -f3 | cut -d',' -f1 | tr '[:upper:]' '[:lower:]')

        if [[ "$class" == *"factorio"* ]]; then
            unbind_alt
        else
            bind_alt
        fi
    fi
}

socat - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | \
    while read -r line; do handle "$line"; done
