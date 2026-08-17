# zsh reads ~/.zshenv before anything else, and it is the only place ZDOTDIR
# can be set - which is why this one file stays at $HOME while the rest of the
# zsh config lives under $ZDOTDIR.
#
# Keeping ZDOTDIR means oh-my-zsh writes its .zcompdump caches into
# ~/.config/zsh instead of littering $HOME.

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
