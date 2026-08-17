#!/usr/bin/env bash
# Distro abstraction. Sourced by every script in runs/.
#
# Package names differ enough between Fedora and Ubuntu that a shared list
# breaks: `dnf install nodejs` has no match on Fedora 44, and because we pass
# -y, one bad name aborts the whole batch. So callers use canonical names and
# pkg_name() maps them per distro.

source /etc/os-release

OS="$ID"

case "$OS" in
    ubuntu | debian)
        PKG_MANAGER="apt"
        ;;
    fedora)
        PKG_MANAGER="dnf"
        ;;
    *)
        echo "Unsupported OS: $OS" >&2
        return 1 2>/dev/null || exit 1
        ;;
esac

# apt needs an index refresh before the first install, but doing it at source
# time meant every runs/* script paid for a full update. Do it once, lazily.
_APT_UPDATED=0

apt_update_once() {
    [[ "$PKG_MANAGER" == "apt" ]] || return 0
    ((_APT_UPDATED)) && return 0
    sudo apt-get update
    _APT_UPDATED=1
}

# Canonical name -> distro name. Echoing nothing means "skip on this distro"
# (the package doesn't exist because it's bundled elsewhere).
pkg_name() {
    local p="$1"

    case "$PKG_MANAGER:$p" in
        # Fedora 44. Verified against the repos, not guessed.
        dnf:go) echo "golang" ;;
        dnf:nodejs) echo "nodejs22" ;;
        dnf:npm) echo "nodejs22-npm" ;;
        dnf:ffmpeg) echo "ffmpeg-free" ;; # real ffmpeg needs RPM Fusion
        dnf:php-zip) echo "php-pecl-zip" ;;
        dnf:php-curl) echo "" ;;          # ships inside php-common

        # Ubuntu. UNVERIFIED - no Ubuntu box to test against yet.
        apt:go) echo "golang-go" ;;
        apt:libnotify) echo "libnotify-bin" ;;
        apt:util-linux) echo "util-linux" ;;
        apt:gtk3) echo "libgtk-3-bin" ;;

        *) echo "$p" ;;
    esac
}

# Fedora ships no Hyprland, ghostty or neovim-nightly of its own - they come
# from COPR. Enabling those repos was done by hand on the workstation, which is
# why a fresh machine could not reproduce it.
enable_copr() {
    local repo="$1"

    [[ "$PKG_MANAGER" == "dnf" ]] || {
        echo "  skip copr $repo (not dnf)"
        return 0
    }

    if dnf repolist 2>/dev/null | grep -qi "copr.*${repo//\//:}"; then
        echo "  copr already enabled: $repo"
        return 0
    fi

    echo "  enabling copr: $repo"
    sudo dnf -q -y copr enable "$repo"
}

install_packages() {
    local canonical mapped
    local -a resolved=()

    for canonical in "$@"; do
        mapped="$(pkg_name "$canonical")"

        if [[ -z "$mapped" ]]; then
            echo "  skip: $canonical (not a separate package on $OS)"
            continue
        fi

        [[ "$mapped" != "$canonical" ]] && echo "  map:  $canonical -> $mapped"
        resolved+=("$mapped")
    done

    if ((${#resolved[@]} == 0)); then
        echo "  nothing to install"
        return 0
    fi

    case "$PKG_MANAGER" in
        apt)
            apt_update_once
            sudo apt-get install -y "${resolved[@]}"
            ;;
        dnf)
            sudo dnf install -y "${resolved[@]}"
            ;;
    esac
}
