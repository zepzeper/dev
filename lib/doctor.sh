#!/usr/bin/env bash
# `dev-env doctor`. Sourced by dev-env, which supplies DEV_ENV_HOME,
# active_packages and the ui helpers.

DOCTOR_PROBLEMS=0

ok() { printf '  \033[1;32mok\033[0m    %s\n' "$*"; }
bad() {
    printf '  \033[1;31mfail\033[0m  %s\n' "$*"
    DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
}
hint() { printf '        \033[2m%s\033[0m\n' "$*"; }

# Everything stow is expected to link. .git is excluded because stow ignores it
# by default, and for the nvim submodule it is a file rather than a directory.
env_files() {
    local pkg
    for pkg in $(active_packages); do
        find "$DEV_ENV_HOME/$pkg" -type f \
            -not -path '*/.git/*' -not -name '.git' \
            -printf '%P\n'
    done | sort -u
}

# Same list, but paired with the package each file came from, so callers can
# resolve a $HOME-relative path back to its source.
env_files_with_pkg() {
    local pkg
    for pkg in $(active_packages); do
        find "$DEV_ENV_HOME/$pkg" -type f \
            -not -path '*/.git/*' -not -name '.git' \
            -printf "$pkg %P\n"
    done | sort -u -k2
}

check_profile() {
    local profile
    profile="$(detect_profile)"

    if [[ -z "$profile" ]]; then
        bad "no session profile detected (neither hyprctl nor i3 found)"
        hint "install a session, or pin one: ./dev-env profile hypr"
    elif [[ -d "$DEV_ENV_HOME/env-$profile" ]]; then
        ok "profile: $profile ($(active_packages | tr '\n' ' '))"
    else
        bad "profile '$profile' has no env-$profile directory"
    fi
}

# Mason is a second provisioning system that runs/ knows nothing about: the
# LSPs, linters, formatters and tree-sitter-cli all come from it. `dev-env all`
# therefore does not give a working editor - nvim has to start once - and
# nothing surfaced that until something failed at the point of use.
check_mason() {
    local cfg="$DEV_ENV_HOME/env-common/.config/nvim/lua/plugins/lsp.lua"
    local pkgdir="$HOME/.local/share/nvim/mason/packages"

    [[ -f "$cfg" ]] || {
        ok "mason: no nvim config (submodule not checked out)"
        return 0
    }

    if [[ ! -d "$pkgdir" ]]; then
        bad "mason has never run - no LSPs, formatters or tree-sitter yet"
        hint "nvim --headless +MasonToolsInstallSync +qa"
        return 0
    fi

    local -a want=() absent=()
    local pkg
    while IFS= read -r pkg; do want+=("$pkg"); done < <(
        sed -n '/ensure_installed = {/,/^      },/p' "$cfg" |
            grep -vE '^\s*--' |
            grep -oE '"[A-Za-z0-9._-]+"' |
            tr -d '"' | sort -u
    )

    ((${#want[@]})) || {
        ok "mason: nothing declared"
        return 0
    }

    for pkg in "${want[@]}"; do
        [[ -d "$pkgdir/$pkg" ]] || absent+=("$pkg")
    done

    if ((${#absent[@]})); then
        bad "mason packages missing (${#absent[@]}/${#want[@]}): ${absent[*]}"
        hint "nvim --headless +MasonToolsInstallSync +qa"
    else
        ok "mason: ${#want[@]} declared tools installed"
    fi
}

# The lid drop-in is root-owned and outside stow, so `link` cannot restore it
# and nothing would notice it had gone until the laptop suspended itself on a
# closed lid at the desk - which looks like a crash, not a config problem.
check_lid() {
    [[ "$(detect_profile)" == "i3" ]] || return 0

    # The workstation runs i3 too and has no lid at all, so there is nothing
    # for the drop-in to say there - reporting it missing would be a failure
    # that cannot be fixed and does not matter.
    compgen -G '/proc/acpi/button/lid/*' >/dev/null || return 0

    local conf=/etc/systemd/logind.conf.d/10-lid.conf

    if [[ ! -f "$conf" ]]; then
        bad "no lid drop-in: a closed lid will suspend even with a monitor attached"
        hint "./dev-env i3"
    elif grep -q '^HandleLidSwitchDocked=ignore' "$conf"; then
        ok "lid: docked lid-close ignored"
    else
        bad "$conf does not set HandleLidSwitchDocked=ignore"
        hint "./dev-env i3 rewrites it"
    fi

    return 0
}

# A bare i3 session starts no polkit agent, and without one anything needing
# admin authorisation fails with no dialog and no visible reason - the failure
# mode the VPN password had. The i3 config execs whichever of the known agents
# is present, so the check is the same list.
check_polkit() {
    [[ "$(detect_profile)" == "i3" ]] || return 0

    local a
    for a in /usr/libexec/polkit-mate-authentication-agent-1 \
        /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 \
        /usr/libexec/polkit-gnome-authentication-agent-1; do
        [[ -x "$a" ]] && {
            ok "polkit agent: ${a##*/}"
            return 0
        }
    done

    bad "no polkit agent installed - admin prompts will fail silently"
    hint "./dev-env i3"
    return 0
}

# xss-lock is the whole locking story in one process: idle, suspend and the
# keybinding all reach i3lock through it. When it is not running the screen
# simply never locks - $mod+Ctrl+l goes to logind and logind finds nobody
# listening - and nothing anywhere says so, which is the worst way for a lock
# to fail.
check_lock() {
    [[ "$(detect_profile)" == "i3" ]] || return 0
    [[ -n "${DISPLAY:-}" ]] || return 0

    if ! pgrep -x xss-lock >/dev/null; then
        bad "xss-lock is not running - nothing locks this screen"
        hint "restart i3 (\$mod+Ctrl+r) - a reload does not re-run exec_always"
        return 0
    fi

    ok "xss-lock running (idle, suspend and \$mod+Ctrl+l)"

    # xss-lock only learns about idle from the X screensaver timer, which is
    # off by default - so it can be running and still never fire on idle.
    local timeout
    # || true, not just 2>/dev/null: with pipefail set, a missing xset makes the
    # whole pipeline non-zero and the command substitution takes doctor down
    # with it - which is exactly the machine this check exists for.
    timeout="$(xset q 2>/dev/null | awk '/timeout:/ { print $2; exit }' || true)"

    if [[ -z "$timeout" ]]; then
        bad "xset is missing - the idle timeout was never set"
        hint "./dev-env i3"
    elif [[ "$timeout" == "0" ]]; then
        bad "screensaver timeout is 0 - the screen locks on suspend but never on idle"
        hint "restart i3 (\$mod+Ctrl+r)"
    else
        ok "idle lock after ${timeout}s"
    fi

    # The other half of "idle locks": logind must not also be acting on idle,
    # or the machine suspends itself behind the lock screen. Asked of the
    # running logind rather than read out of the drop-in, because a file that
    # was never reloaded says nothing about current behaviour.
    local idle
    idle="$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager IdleAction 2>/dev/null || true)"

    case "$idle" in
        '') ;; # no logind to ask - nothing to assert
        *'"ignore"'*) ok "logind idle action: ignore (locks, never suspends)" ;;
        *)
            bad "logind idle action is ${idle#s }, so the machine suspends itself on idle"
            hint "./dev-env i3"
            ;;
    esac

    return 0
}

# flameshot's portal bypass. It is a key inside a file flameshot itself
# rewrites, so it cannot be stowed and nothing but this notices when it is lost
# - and the symptom is a screenshot key that appears to do nothing for 30
# seconds before failing.
check_flameshot() {
    [[ "$(detect_profile)" == "i3" ]] || return 0
    command -v flameshot >/dev/null || return 0

    local ini="$HOME/.config/flameshot/flameshot.ini"

    if grep -qx 'useX11LegacyScreenshot=true' "$ini" 2>/dev/null; then
        ok "flameshot bypasses the screenshot portal"
    else
        bad "flameshot will ask the screenshot portal - nothing serves it on i3"
        hint "./dev-env i3"
    fi

    return 0
}

# The machine-wide variables runs/env writes. Root-owned and outside stow, so
# `link` cannot restore them - and because they are read only at login, the
# file being right says nothing about the running session having them. Both are
# checked: one catches a machine that never ran the installer, the other a
# session that predates it.
check_system_env() {
    local file=/etc/environment

    if grep -q '^# >>> dev-env' "$file" 2>/dev/null; then
        ok "system variables written to $file"
    else
        bad "no dev-env block in $file - theme variables are unset machine-wide"
        hint "./dev-env env"
        return 0
    fi

    # Only meaningful inside a session that would have picked them up.
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || return 0

    if [[ -n "${GTK_THEME:-}" ]]; then
        ok "session has them: GTK_THEME=$GTK_THEME"
    else
        bad "this session has no GTK_THEME - it predates ./dev-env env"
        hint "log out and back in"
    fi

    return 0
}

# Dark mode is half tracked file, half dconf key, and only the file half is
# restored by `link`. The dconf half is what the portal reports to Firefox,
# Electron, GTK4 and nvim's auto-dark-mode, so when it drifts - a GNOME session
# logged into once is enough - those apps go light while the GTK3 ones stay
# dark, which reads as an app bug rather than a setting.
check_theme() {
    command -v gsettings >/dev/null || return 0

    local scheme
    scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)"

    case "$scheme" in
        "'prefer-dark'") ok "color scheme: prefer-dark" ;;
        "")
            bad "color-scheme key unreadable - gsettings-desktop-schemas missing?"
            hint "./dev-env theme"
            ;;
        *)
            bad "color scheme is $scheme, not 'prefer-dark'"
            hint "./dev-env theme"
            ;;
    esac

    # dconf is only where the preference is stored; the Settings portal is what
    # apps read it through, and under i3 that runs only because
    # i3-session.target brings graphical-session.target up. Checked separately
    # because the two fail apart: the key can be perfect while every browser
    # still renders light.
    #
    # Skipped outside a graphical session - over ssh there is no portal to ask
    # and its absence means nothing.
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || return 0
    command -v gdbus >/dev/null || return 0

    local reported
    reported="$(gdbus call --session --dest org.freedesktop.portal.Desktop \
        --object-path /org/freedesktop/portal/desktop \
        --method org.freedesktop.portal.Settings.ReadOne \
        org.freedesktop.appearance color-scheme 2>/dev/null || true)"

    case "$reported" in
        *"uint32 1"*) ok "settings portal reports: dark" ;;
        "")
            bad "the settings portal is not answering - apps fall back to light"
            hint "systemctl --user start i3-session.target"
            ;;
        *)
            bad "the settings portal reports $reported, not dark (uint32 1)"
            hint "./dev-env theme"
            ;;
    esac

    return 0
}

# env-hypr's launch-tui hands the terminal choice to xdg-terminal-exec so that
# --app-id lands on whichever flag that terminal uses. Without a
# xdg-terminals.list the choice comes from scanning desktop entries, and any
# newly installed terminal can quietly take it over - the keybindings still
# work, they just stop opening ghostty and stop picking up its config.
check_terminal() {
    [[ "$(detect_profile)" == "hypr" ]] || return 0

    local wanted=com.mitchellh.ghostty.desktop got

    if ! command -v xdg-terminal-exec >/dev/null; then
        bad "xdg-terminal-exec not installed - launch-tui cannot open anything"
        hint "./dev-env hyprland"
        return 0
    fi

    got="$(xdg-terminal-exec --print-id 2>/dev/null)"

    if [[ "$got" == "$wanted" ]]; then
        ok "terminal: ghostty"
    elif [[ -z "$got" ]]; then
        bad "xdg-terminal-exec finds no terminal at all"
        hint "install ghostty, then re-run"
    else
        bad "launch-tui would open $got, not ghostty"
        hint "if ~/.config/xdg-terminals.list is linked, ghostty is not installed: ./dev-env ghostty"
    fi

    return 0
}

check_stow() {
    if command -v stow >/dev/null; then
        ok "stow present ($(stow --version | head -1))"
    else
        bad "stow not installed"
        hint "./dev-env link installs it automatically"
    fi
}

# Each file under env/ should exist at $HOME as a symlink resolving back here.
check_links() {
    local rel target src missing=0 conflict=0 foreign=0 broken=0 linked=0 pkg_map
    pkg_map="$(env_files_with_pkg)"

    while IFS= read -r rel; do
        target="$HOME/$rel"
        src="$DEV_ENV_HOME/$(awk -v r="$rel" '$2 == r {print $1; exit}' <<<"$pkg_map")/$rel"

        if [[ -L "$target" ]]; then
            if [[ ! -e "$target" ]]; then
                bad "dangling link: ~/$rel"
                broken=$((broken + 1))
            elif [[ "$(readlink -f "$target")" != "$(readlink -f "$src")" ]]; then
                bad "links elsewhere: ~/$rel -> $(readlink "$target")"
                foreign=$((foreign + 1))
            else
                linked=$((linked + 1))
            fi
        elif [[ -e "$target" ]]; then
            bad "real file blocks stow: ~/$rel"
            hint "inspect it, then delete it and re-run ./dev-env link"
            conflict=$((conflict + 1))
        else
            bad "not linked: ~/$rel"
            missing=$((missing + 1))
        fi
    done < <(env_files)

    ((missing + conflict + foreign + broken == 0)) &&
        ok "$linked files linked from env/"

    ((missing)) && hint "$missing missing - run ./dev-env link"
    return 0
}

# Files that moved or were deleted inside the repo leave links behind at $HOME:
# unstow only knows about the package's *current* contents, so it cannot clean
# them up. Scan just the directories the packages populate, not all of $HOME.
#
# Deliberately walks *every* env-* package, not only the active ones. Switching
# profiles - or splitting one package into several - strands links in
# directories the active profile no longer touches, and scanning only the
# active set would report those as clean.
check_orphans() {
    local -a dirs=()
    local rel d pkg found=0

    for pkg in "$DEV_ENV_HOME"/env-*; do
        [[ -d "$pkg" ]] || continue
        while IFS= read -r rel; do
            dirs+=("$HOME/$(dirname "$rel")")
        done < <(find "$pkg" -type f -not -path '*/.git/*' -not -name '.git' -printf '%P\n')
    done

    while IFS= read -r d; do
        [[ -d "$d" ]] || continue
        while IFS= read -r l; do
            [[ -e "$l" ]] && continue
            case "$(readlink "$l")" in
                *personal/dev/* | *.dotfiles*)
                    bad "orphaned link: ${l/#$HOME/\~} -> $(readlink "$l")"
                    hint "left over from a moved/deleted file; rm it"
                    found=$((found + 1))
                    ;;
            esac
        done < <(find "$d" -maxdepth 1 -type l 2>/dev/null)
    done < <(printf '%s\n' "${dirs[@]}" | sort -u)

    ((found == 0)) && ok "no orphaned links"
    return 0
}

check_submodules() {
    local line status path

    # IFS= matters: read would otherwise strip the leading status character
    # when it is a space (the "clean" case).
    while IFS= read -r line; do
        status="${line:0:1}"
        path="$(echo "${line:1}" | awk '{print $2}')"

        case "$status" in
            -)
                bad "submodule not initialized: $path"
                hint "git submodule update --init $path"
                ;;
            +)
                bad "submodule at a different commit than recorded: $path"
                hint "commit the pointer, or: git submodule update $path"
                ;;
            U) bad "submodule has merge conflicts: $path" ;;
            *) ok "submodule $path" ;;
        esac

        if [[ -d "$DEV_ENV_HOME/$path" ]]; then
            if [[ -n "$(git -C "$DEV_ENV_HOME/$path" status --porcelain 2>/dev/null)" ]]; then
                bad "submodule has uncommitted changes: $path"
                hint "dev-commit handles submodule-then-superproject ordering"
            fi
        fi
    done < <(git -C "$DEV_ENV_HOME" submodule status 2>/dev/null)

    return 0
}

check_repo() {
    local ahead

    if [[ -n "$(git -C "$DEV_ENV_HOME" status --porcelain)" ]]; then
        bad "repo has uncommitted changes"
        hint "dev-commit"
    else
        ok "repo clean"
    fi

    if git -C "$DEV_ENV_HOME" remote get-url origin >/dev/null 2>&1; then
        ahead="$(git -C "$DEV_ENV_HOME" rev-list --count '@{u}'..HEAD 2>/dev/null || echo 0)"
        if [[ "$ahead" != "0" ]]; then
            bad "$ahead commit(s) not pushed"
        else
            ok "pushed"
        fi
    else
        bad "no origin remote"
    fi

    return 0
}

# Catches the stale-shell case: the profile is correct on disk but the running
# shell predates it, so nothing under .local/scripts resolves.
check_path() {
    local d
    for d in "$HOME/.local/scripts" "$HOME/.local/bin"; do
        case ":$PATH:" in
            *":$d:"*) ok "on PATH: ${d/#$HOME/\~}" ;;
            *)
                bad "not on PATH: ${d/#$HOME/\~}"
                hint "your shell predates the profile change - run: exec zsh"
                ;;
        esac
    done
    return 0
}

do_doctor() {
    info "profile"
    check_profile
    info "tooling"
    check_stow
    check_lid
    check_polkit
    check_lock
    check_flameshot
    check_system_env
    check_theme
    check_terminal
    check_mason
    info "PATH"
    check_path
    info "links"
    check_links
    check_orphans
    info "submodules"
    check_submodules
    info "repo"
    check_repo

    if ((DOCTOR_PROBLEMS)); then
        printf '\n\033[1;31m%d problem(s) found\033[0m\n' "$DOCTOR_PROBLEMS"
        return 1
    fi

    printf '\n\033[1;32mall good\033[0m\n'
    return 0
}
