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
