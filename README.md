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

### zsh

`env/.zshenv` is the one zsh file that has to sit at `$HOME` — it is read
first and is the only place `ZDOTDIR` can be set. It points `ZDOTDIR` at
`~/.config/zsh`, so everything else lives in `env/.config/zsh/`. That also
keeps oh-my-zsh's `.zcompdump` caches out of `$HOME`.

Consequence worth remembering: with `ZDOTDIR` set, a `~/.zshrc` is **ignored
entirely**. If zsh ever seems to load the wrong config, check `echo $ZDOTDIR`
first.

## Bootstrap a machine

Only `git` has to pre-exist. `stow` is the one tool the linking step itself
depends on, so `dev-env` installs it on demand rather than assuming it — that
way `link` works on a bare machine before any installer has run. It is also in
`runs/dev`, so a normal full run keeps it up to date.

```sh
git clone --recurse-submodules git@github.com:zepzeper/dev.git ~/personal/dev
cd ~/personal/dev
./dev-env all
```

`all` links `env/` into `$HOME` and runs every installer. It is spelled out
rather than being the default because it installs packages system-wide — a
bare `./dev-env` prints help and changes nothing. Piecemeal:

```sh
./dev-env --list          # available installers
./dev-env link            # symlinks only, no packages
./dev-env dev docker      # just those two
./dev-env unlink          # back it out
./dev-env doctor          # check this machine for problems
```

## doctor

`./dev-env doctor` checks the machine and exits non-zero if anything is wrong:

- every file under `env/` is linked at `$HOME` and resolves back into the repo
- no orphaned links — files that move *inside* the repo leave links behind at
  `$HOME`, because unstow only knows the package's current contents
- no real files blocking stow
- submodules initialized, at the recorded commit, and clean
- repo committed and pushed
- `~/.local/scripts` and `~/.local/bin` on `PATH` — catches the case where the
  config is right on disk but your running shell predates it (`exec zsh`)

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

## Secrets

SSH keys and recovery codes live encrypted under `secrets/`, managed by
`dev-secrets`. See [secrets/README.md](secrets/README.md) for the details and
the trade-offs.

The bootstrap order matters, because the SSH key needed to clone this repo
lives *inside* it. Clone over HTTPS first:

```sh
git clone https://github.com/zepzeper/dev.git ~/personal/dev
cd ~/personal/dev
./dev-env age                      # install age
dev-secrets unlock                 # passphrase from Bitwarden -> writes ~/.ssh/id_ed25519
git remote set-url origin git@github.com:zepzeper/dev.git
git submodule update --init --recursive
./dev-env all
```

Submodules are cloned after the key is in place, since `env/.config/nvim` uses
an SSH URL. Cloning with `--recurse-submodules` up front would fail.

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
