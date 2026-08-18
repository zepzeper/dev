#!/bin/sh
# Launched by `startx`. Display managers read ~/.xprofile themselves, but xinit
# does not, so source it here to get ~/.local/scripts and ~/.local/bin on PATH.
[ -f "$HOME/.xprofile" ] && . "$HOME/.xprofile"

exec i3
