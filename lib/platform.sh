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
        dnf:php-curl) echo "" ;; # ships inside php-common
        dnf:pkg-config) echo "pkgconf-pkg-config" ;;
        dnf:helium) echo "helium-bin" ;;
        dnf:shellcheck) echo "ShellCheck" ;;
        dnf:ayatana-appindicator) echo "libayatana-appindicator-gtk3" ;;
        dnf:networkmanager) echo "NetworkManager" ;;
        dnf:networkmanager-tui) echo "NetworkManager-tui" ;;
        dnf:networkmanager-applet) echo "network-manager-applet" ;;
        dnf:networkmanager-openvpn) echo "NetworkManager-openvpn-gnome" ;;
        dnf:rfkill) echo "util-linux" ;; # Fedora never split it out
        dnf:python3-venv) echo "" ;;     # ships inside python3-libs
        # X11, for the i3 session. Fedora splits what Ubuntu ships as the
        # xorg/xinit/x11-xserver-utils trio, and retired xorg-x11-server-utils
        # outright - xrandr, the only tool out of it this repo calls (i3's
        # monitor and monitor-watch), is a package of its own now.
        dnf:xorg) echo "xorg-x11-server-Xorg" ;;
        dnf:xinit) echo "xorg-x11-xinit" ;;
        dnf:x11-xserver-utils) echo "xrandr" ;;
        # polkit-gnome is retired on Fedora 44, and the Hyprland session brings
        # its own agent - but i3 does not, so Fedora needs one too. mate-polkit
        # is the same GTK3 agent under another name: it pulls gtk3 and
        # appindicator, not MATE. The i3 config execs its libexec path.
        dnf:polkit-agent) echo "mate-polkit" ;;

        # Ubuntu. Verified on noble (24.04) in a dev-vm guest.
        apt:go) echo "golang-go" ;;
        apt:libnotify) echo "libnotify-bin" ;;
        apt:util-linux) echo "util-linux" ;;
        apt:gtk3) echo "libgtk-3-bin" ;;
        apt:dbus-devel) echo "libdbus-1-dev" ;;
        apt:ayatana-appindicator) echo "libayatana-appindicator3-1" ;;

        # Not yet exercised in a dev-vm guest, unlike the entries above - these
        # are the noble archive names, so treat a failure here as a name to fix
        # rather than a missing package.
        apt:networkmanager) echo "network-manager" ;;
        apt:networkmanager-tui) echo "" ;; # nmtui ships inside network-manager
        apt:networkmanager-applet) echo "network-manager-gnome" ;;
        # The -gnome package, not the bare plugin: it carries the auth dialog
        # nm-applet needs to prompt for the VPN password. Without it a connect
        # attempt fails with no visible reason.
        apt:networkmanager-openvpn) echo "network-manager-openvpn-gnome" ;;
        apt:pipewire-devel) echo "libpipewire-0.3-dev" ;;
        apt:clang-devel) echo "libclang-dev" ;; # bindgen needs libclang
        apt:polkit-agent) echo "policykit-1-gnome" ;;

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

# Ubuntu's archives freeze a language's version for the life of the release -
# noble is stuck on php 8.3 while Fedora 44 ships 8.5 - so matching the two
# machines means pulling from a PPA.
enable_ppa() {
    local ppa="$1"

    [[ "$PKG_MANAGER" == "apt" ]] || {
        echo "  skip ppa $ppa (not apt)"
        return 0
    }

    if grep -rqs "^deb .*${ppa#ppa:}" /etc/apt/sources.list.d/ 2>/dev/null; then
        echo "  ppa already enabled: $ppa"
        return 0
    fi

    command -v add-apt-repository >/dev/null || {
        apt_update_once
        sudo apt-get install -y software-properties-common
    }

    echo "  enabling ppa: $ppa"
    sudo add-apt-repository -y "$ppa"
    _APT_UPDATED=0 # the new repo needs indexing
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
