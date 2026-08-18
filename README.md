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
env-common/          dotfiles for every machine
env-hypr/            Hyprland session: compositor, waybar, launch-* scripts
env-i3/              i3 session: i3, i3status, .xprofile
secrets/             age-encrypted secrets
resources/           vendored third-party tools (submodule)
```

Each `env-*` is a literal `$HOME` mirror, so linking is just `stow`. A file at
`env-common/.config/tmux/tmux.conf` lands at `~/.config/tmux/tmux.conf`.

## Profiles

`env-common` is stowed everywhere; exactly one session profile joins it. The
laptop runs i3 on X11 and must not receive Hyprland configs or the `launch-*`
scripts, all of which shell out to `hyprctl` or `uwsm-app` and would fail there.

```sh
./dev-env profile            # what this machine resolved to
./dev-env profile i3         # pin it (writes .dev-profile, untracked)
```

Detection order: `$DEV_ENV_PROFILE`, then `.dev-profile`, then whichever of
`hyprctl` / `i3` is installed. On a bare machine neither exists yet, so `link`
stows `env-common` only — re-run it after `runs/desktop`.

### zsh

`env-common/.zshenv` is the one zsh file that has to sit at `$HOME` — it is read
first and is the only place `ZDOTDIR` can be set. It points `ZDOTDIR` at
`~/.config/zsh`, so everything else lives in `env-common/.config/zsh/`. That also
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

`all` links the active profile into `$HOME` and runs every installer. It is spelled out
rather than being the default because it installs packages system-wide — a
bare `./dev-env` prints help and changes nothing. Piecemeal:

```sh
./dev-env --list          # available installers
./dev-env link            # symlinks only, no packages
./dev-env dev docker      # just those two
./dev-env unlink          # back it out
./dev-env doctor          # check this machine for problems
```

## Hooks

`dev-env link` points `core.hooksPath` at the tracked `hooks/` directory, so
the pre-commit lint applies on every machine instead of living untracked in
`.git/hooks`. It shellchecks only the staged shell scripts — linting the whole
repo on every commit is slow enough that it would get bypassed out of habit.
`git commit --no-verify` skips it.

## Keeping a machine current

```sh
./dev-env update          # pull, submodules, relink, doctor
./dev-env update --all    # and re-run every installer
```

`update` names the `runs/` scripts that changed since the last pull, because
linking cannot re-provision — a new package in `runs/dev` needs that installer
run, not just a relink.

It refuses on a dirty tree rather than pulling over local edits, ignoring
submodules since nvim's `lazy-lock.json` is dirty as a matter of course. And it
re-execs itself after a pull that changed `dev-env`, so the relink and doctor
come from the new code rather than the version that started.

## doctor

`./dev-env doctor` checks the machine and exits non-zero if anything is wrong:

- every file under each active `env-*` is linked at `$HOME` and resolves back into the repo
- no orphaned links — files that move *inside* the repo leave links behind at
  `$HOME`, because unstow only knows the package's current contents
- no real files blocking stow
- submodules initialized, at the recorded commit, and clean
- repo committed and pushed
- mason's declared tools are installed — the LSPs, linters, formatters and
  `tree-sitter-cli` come from mason, not `runs/`, so `dev-env all` alone does
  not give a working editor; nvim has to start once
- `~/.local/scripts` and `~/.local/bin` on `PATH` — catches the case where the
  config is right on disk but your running shell predates it (`exec zsh`)

## Submodules

| Path | Repo |
| --- | --- |
| `env-common/.config/nvim` | `zepzeper/nvim` |
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
./dev-env bootstrap
```

`bootstrap` runs that whole sequence: install age, unlock secrets (prompts once
for the passphrase), switch `origin` from https to ssh, fetch the submodules,
link, and run the installers. It is idempotent — if the key is already present
it skips straight to linking.

Submodules are cloned after the key is in place, since `env-common/.config/nvim` uses
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

Both columns are verified: Fedora against the repos, Ubuntu by running
`./dev-env dev` in a noble guest (see `dev-vm`). Everything in `runs/dev`
resolved there, `just` included — it is in noble's archives despite not being
in older releases.

## Environment

`env-common/.config/personal/env` is the single source of truth for `PATH` and
the exported variables. `.profile` sources it, `.xprofile` sources `.profile`,
and `.zsh_profile` picks it up with everything else in that directory — so bash
and zsh cannot drift apart, which they had.

`path_add` only adds a directory that exists and never adds one twice. Nine of
the previous entries pointed at directories that were never created and
`~/.local/apps` was listed twice.

Hyprland sets its cursor variables again in `envs.lua`, deliberately: a
compositor started by uwsm never reads a login shell.

## Known gaps

- `runs/ghostty` on Ubuntu installs a community `.deb` from
  `mkasberg/ghostty-ubuntu`, since upstream ships none and a source build needs
  zig 0.16-dev. It tracks the same upstream version the Fedora copr provides.
- `runs/i3` is Ubuntu-only by design; Fedora runs Hyprland.
- `launch-menu` calls `launch-screenrecorder` and `localsend_app`, and the hypr
  `SUPER+SHIFT+O` binding calls `~/.local/bin/llm.sh`. None of the three exist
  in this repo or on disk, so those branches stay broken.
- There is no wifi launcher. `impala` was dropped (it drives **iwd**, while
  these machines run NetworkManager) and waybar's network module is now
  display-only - the workstation is on ethernet.
- `runs/hyprland`, `runs/nvim` and the copr path in `runs/ghostty` need sudo and
  have not been run end to end yet - only `runs/tui` and `runs/fonts` have.
- `env-common/.local/scripts/misc/tmux-sessionizer` is the old homegrown sessionizer,
  superseded by the vendored one but kept for reference.
