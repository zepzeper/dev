#!/usr/bin/env bash

# Pick project
if [[ $# -eq 1 ]]; then
    selected="$1"
else
    selected=$(
        {
            # Top-level personal + work (excluding playground)
            find "$HOME"/{personal,work} \
                -mindepth 1 -maxdepth 1 -type d \
                ! -path "$HOME/personal/playground"

                # Separate search INSIDE playground
                find "$HOME/personal/playground" \
                    -mindepth 1 -maxdepth 1 -type d
                } | fzf
            )
fi

# Exit if nothing selected
[[ -z "$selected" ]] && exit 0

selected_name=$(basename "$selected" | tr . _)
tmux_running=$(pgrep tmux)

# Function to setup windows
setup_windows() {
    local session="$1"
    local path="$2"
    
    # Window 1: nvim (already created with session)
    tmux send-keys -t "$session:1" "nvim $path" C-m
    
    # Window 2: terminal commands
    tmux new-window -t "$session:2" -n "terminal" -c "$path"
    
    # Window 3: long running process 1
    tmux new-window -t "$session:3" -c "$path"
    
    # Window 4: long running process 2
    tmux new-window -t "$session:4" -c "$path"
    
    # Select the first window (nvim)
    tmux select-window -t "$session:1"
}

# If no tmux at all is running, start a new session with layout
if [[ -z $TMUX ]] && [[ -z $tmux_running ]]; then
    tmux new-session -s "$selected_name" -c "$selected" -d
    setup_windows "$selected_name" "$selected"
    tmux attach -t "$selected_name"
    exit 0
fi

# Check if session exists
session_exists=$(tmux has-session -t "$selected_name" 2>/dev/null; echo $?)

# If the session doesn't exist, create it with the layout
if [[ $session_exists -ne 0 ]]; then
    tmux new-session -ds "$selected_name" -c "$selected"
    setup_windows "$selected_name" "$selected"
fi

# Attach or switch depending if we're in tmux
if [[ -n $TMUX ]]; then
    tmux switch-client -t "$selected_name"
else
    tmux attach -t "$selected_name"
fi
