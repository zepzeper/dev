# dev

Machine setup: dotfiles plus the installers that provision them. Replaces the
old `.dotfiles` repo.

Targets two machines:

| Machine | Distro | Session |
| --- | --- | --- |
| Workstation | Fedora | Hyprland (Wayland) |
| Work laptop | Ubuntu | i3 (X11) |

## Layout

```
dev-env              orchestrator: link dotfiles, run installers
lib/platform.sh      distro detection + per-distro package name map
runs/                one installer per tool
env/                 dotfile payload, mirrors $HOME exactly
resources/           vendored third-party tools (submodule)
```

`env/` is a literal `$HOME` mirror, so linking is just `stow`. A file at
`env/.config/tmux/tmux.conf` lands at `~/.config/tmux/tmux.conf`.

## Bootstrap a machine

```sh
git clone --recurse-submodules git@github.com:zepzeper/dev.git ~/personal/dev
cd ~/personal/dev
./dev-env
```

That links `env/` into `$HOME` and runs every installer. Or piecemeal:

```sh
./dev-env --list          # available installers
./dev-env link            # symlinks only, no packages
./dev-env dev docker      # just those two
./dev-env unlink          # back it out
```

## Submodules

| Path | Repo |
| --- | --- |
| `env/.config/nvim` | `zepzeper/nvim` |
| `resources/tmux-sessionizer` | `ThePrimeagen/tmux-sessionizer` |

Neovim is its own repo because it churns far more than everything else
combined. It is a submodule, so committing an nvim change is two steps:

```sh
dev-commit                # handles both, in the right order
```

Submodule first, then the superproject — otherwise the pointer this repo
records refers to a commit that exists only on your machine.

To pull third-party updates:

```sh
git submodule update --remote resources/tmux-sessionizer
```

## Package names

Names diverge between distros badly enough that a shared list silently breaks.
`dnf install nodejs` has no match on Fedora 44, and since installs pass `-y`,
one bad name aborts the whole batch. `pkg_name()` in `lib/platform.sh` maps
canonical names per distro:

| Canonical | Fedora 44 | Ubuntu |
| --- | --- | --- |
| `go` | `golang` | `golang-go` |
| `nodejs` | `nodejs22` | `nodejs` |
| `npm` | `nodejs22-npm` | `npm` |
| `ffmpeg` | `ffmpeg-free` | `ffmpeg` |
| `php-zip` | `php-pecl-zip` | `php-zip` |
| `php-curl` | *(in `php-common`)* | `php-curl` |

The Fedora column is verified against the repos. **The Ubuntu column is not** —
it has not been run on the laptop yet.

## Known gaps

- `runs/ghostty` cannot install on Ubuntu; upstream ships no `.deb`, so it
  prints build instructions instead. `~/personal/ghostty/zig-out/bin` is
  already on `PATH` for that case.
- `runs/i3` is Ubuntu-only by design; Fedora runs Hyprland.
- `env/.config/hypr/scripts/game-submap.sh` (unbinds ALT keys while Factorio is
  focused) is not wired into anything. It needs an `hl.exec_cmd` line in
  `env/.config/hypr/autostart.lua` to actually run.
- `env/.local/scripts/misc/tmux-sessionizer` is the old homegrown sessionizer,
  superseded by the vendored one but kept for reference.
