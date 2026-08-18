#!/usr/bin/env bash
# Helpers for tools that are not packaged and come from upstream releases.
#
# Four installers were each hand-rolling the same github API query, and five
# were each repeating download -> extract -> move to ~/.local -> symlink.

# Skip an installer when the command is already there. Callers use:
#   have odin && exit 0
have() {
    command -v "$1" >/dev/null || return 1
    echo "$1 already installed: $(command -v "$1")"
    return 0
}

# Resolve a release asset URL. <pattern> is a grep -E over the asset names, so
# callers stay in charge of arch/libc/format selection.
#   github_asset odin-lang/Odin "odin-linux-amd64.*\.tar\.gz"
github_asset() {
    local repo="$1" pattern="$2" url

    url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
        grep '"browser_download_url":' |
        grep -E "$pattern" |
        head -n1 |
        sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/')"

    [[ -n "$url" ]] || {
        echo "no asset matching '$pattern' in $repo" >&2
        return 1
    }

    printf '%s' "$url"
}

# Map uname -m onto the naming a project actually uses.
#   arch_name amd64 arm64   -> amd64 on x86_64
arch_name() {
    case "$(uname -m)" in
        x86_64) printf '%s' "$1" ;;
        aarch64 | arm64) printf '%s' "$2" ;;
        *)
            echo "unsupported architecture: $(uname -m)" >&2
            return 1
            ;;
    esac
}

# Download an archive, unpack it, and install it as ~/.local/<name> with
# <name>/<relbin> symlinked onto PATH. Handles the single-top-level-directory
# layout every one of these projects happens to use.
#
#   install_release odin "$url" odin
install_release() {
    local name="$1" url="$2" relbin="${3:-$1}"
    local dest="$HOME/.local/$name"
    local tmp
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    echo "downloading $(basename "$url")"
    curl --fail --location --progress-bar "$url" --output "$tmp/archive"

    case "$url" in
        *.tar.gz | *.tgz) tar -xzf "$tmp/archive" -C "$tmp" ;;
        *.tar.xz) tar -xJf "$tmp/archive" -C "$tmp" ;;
        *.zip) unzip -qo "$tmp/archive" -d "$tmp" ;;
        *)
            echo "unknown archive type: $url" >&2
            return 1
            ;;
    esac

    rm -f "$tmp/archive"

    # Most archives hold one top-level dir; some unpack flat.
    local src
    src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    [[ -n "$src" ]] || src="$tmp"

    rm -rf "$dest"
    mkdir -p "$HOME/.local/bin"
    mv "$src" "$dest"

    [[ -x "$dest/$relbin" ]] || {
        echo "expected $relbin inside the archive" >&2
        return 1
    }

    ln -sfn "$dest/$relbin" "$HOME/.local/bin/${relbin##*/}"
    echo "installed ~/.local/bin/${relbin##*/}"
}
