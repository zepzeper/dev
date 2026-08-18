# Login shells for sh/bash. zsh reads .zshenv -> .zshrc -> .zsh_profile
# instead, which picks up the same file from ~/.config/personal.
[ -f "$HOME/.config/personal/env" ] && . "$HOME/.config/personal/env"
