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

### Displays (i3)

The laptop lives on an external monitor with the lid shut, and only opens for
meetings, so the lid is the switch that picks the layout:

| Lid | External | Result |
| --- | --- | --- |
| closed | yes | external only, primary — the desk default |
| open | yes | both on, laptop primary and to the left |
| closed | no | logind suspends |
| — | no | laptop only, primary |

Two halves have to agree, and only one of them is a dotfile.

`env-i3/.config/i3/monitor` decides the layout and is idempotent, so i3 runs it
at start and on reload, `monitor-watch` runs it on every change, and
`$mod+Shift+s` runs it by hand when a monitor comes back in a state xrandr got
wrong. `monitor-watch` is a 2-second poll rather than a udev rule because
**closing the lid emits no drm uevent** — the panel stays `connected` and only
the ACPI lid button moves, so a udev rule would catch the hotplug and miss the
case the laptop spends its day in. It takes a `flock`, so `exec_always` cannot
stack up a watcher per reload.

The other half is `/etc/systemd/logind.conf.d/10-lid.conf`, written by
`runs/i3`. Without it logind suspends the machine on a closed lid before any of
the above gets a say. It sets `HandleLidSwitchDocked=ignore`, and logind's
"docked" test counts *external* connectors only — it skips eDP/LVDS — so one
monitor attached is enough. `HandleLidSwitch=suspend` keeps the normal
into-the-bag behaviour when nothing is plugged in. **It applies at the next
boot**: restarting `systemd-logind` kills the running session, so `runs/i3`
deliberately does not. The file is root-owned and outside stow's reach, so
`doctor` checks it — `link` could never restore it.

Workspaces are deliberately left where they are when the panel switches on.
i3 already moves them off an output as it is disabled, and dragging them back
mid-meeting is worse than an empty second screen. To pin one, add a
`workspace 5 output eDP-1` line to the i3 config.

### System TUIs (i3)

Audio, wifi, VPN and bluetooth are all TUIs in a floating terminal, the same
tools the workstation uses so the habits carry across:

| Key | Tool | What |
| --- | --- | --- |
| `$mod+Shift+a` | `wiremix` | audio devices and volume (PipeWire) |
| `$mod+Shift+n` | `nmtui connect` | wifi picker |
| `$mod+Ctrl+v` | `nmcli` + rofi | VPN up/down (not `$mod+Shift+v`, which splits) |
| `$mod+b` | `bluetui` | bluetooth |

`launch-tui` spawns them and `launch-or-focus-tui` focuses an already-open one,
so a second keypress does not stack up windows. Both are i3-specific: the
env-hypr twins go through `uwsm-app` and `xdg-terminal-exec`, which are
Wayland-only. Ghostty fills X11's two `WM_CLASS` fields from separate options —
`--class` and `--x11-instance-name` — and `launch-tui` sets both to
`zepzeper.<tool>`, which is what the `for_window` float rule matches and what
keeps the ids identical to the hypr window rules.

Wifi is `nmtui` because these machines run **NetworkManager**. `impala` was the
obvious pick and was dropped for a real reason: it drives **iwd**.

The VPN is an OpenVPN profile NetworkManager owns, so `launch-vpn` drives
`nmcli` rather than `openvpn(8)` — NetworkManager is what installs the routes,
hands DNS to the split-DNS resolver (that stray `dnsmasq` is this, not a VPN of
its own), and lets nm-applet's secret agent prompt for an unsaved password.
Calling `openvpn` by hand gets a tunnel and none of the rest. The launcher
offers every connection NetworkManager types as `vpn` or `wireguard`, so
swapping the profile later needs no change to it. With one profile it toggles
straight away; with several it asks through rofi, `●` connected and `○` not.

The profile itself is **not in this repo** — it carries credentials. Set it up
once per machine, either from an `.ovpn` file:

```sh
nmcli connection import type openvpn file /path/to/profile.ovpn
```

or, for a certificate-based server where all you have is a keypair, by pointing
a new connection at the files. Certs alone are never enough: the **CA
certificate** and the **server address** have to come from whoever runs the VPN,
since nothing in a client `.crt`/`.key` pair says who to trust or where to dial.

```sh
mkdir -p ~/.cert/nm-openvpn && chmod 700 ~/.cert/nm-openvpn
cp ca.crt client.crt client.key ~/.cert/nm-openvpn/
chmod 600 ~/.cert/nm-openvpn/client.key

nmcli connection add type vpn vpn-type openvpn con-name work-vpn ifname '*'
nmcli connection modify work-vpn vpn.data \
  'connection-type=password-tls, remote=vpn.example.com, port=1194, ca=/home/zepzeper/.cert/nm-openvpn/ca.crt, cert=/home/zepzeper/.cert/nm-openvpn/client.crt, key=/home/zepzeper/.cert/nm-openvpn/client.key'
```

Paths in `vpn.data` must be absolute — `~` is not expanded.

#### The password has to be system-owned

This is the one thing that differs from GNOME, and it is worth understanding
rather than working around. A VPN password can be stored three ways, recorded as
`password-flags` in `vpn.data`:

| Flag | Meaning | Works in this i3 session? |
| --- | --- | --- |
| `0` | system-owned, in the connection file | **yes** |
| `1` | agent-owned, in gnome-keyring | no |
| `2` | never saved, always ask | no |

Under GNOME, PAM unlocks gnome-keyring at login, so an agent-owned secret can be
handed to NetworkManager on demand. A bare `startx` i3 session has no unlocked
keyring, and `launch-vpn` runs detached with no tty, so there is nowhere for a
prompt to go either. The failure looks like:

```
password for vpn.secrets.password not given in passwd-file
```

`launch-vpn` recognises that specific case and says so rather than reporting a
generic failure. The fix is to make the secret system-owned, which needs no
agent at all — the same way the wifi PSKs in this session already work:

```sh
nmcli connection modify <NAME> +vpn.data password-flags=0
read -rs -p 'VPN password: ' p && nmcli connection modify <NAME> +vpn.secrets "password=$p"; unset p
```

That writes it to `/etc/NetworkManager/system-connections/<NAME>.nmconnection`,
root-only `0600`. The alternative — starting and PAM-unlocking gnome-keyring in
the i3 session — is more moving parts for the same result on a single-user
laptop, so it is deliberately not done here.

The certs themselves are a good fit for `secrets/`, so a rebuilt machine does
not need someone to re-send them:

```sh
dev-secrets add vpn-ca   ~/.cert/nm-openvpn/ca.crt     '~/.cert/nm-openvpn/ca.crt'     644
dev-secrets add vpn-cert ~/.cert/nm-openvpn/client.crt '~/.cert/nm-openvpn/client.crt' 644
dev-secrets add vpn-key  ~/.cert/nm-openvpn/client.key '~/.cert/nm-openvpn/client.key' 600
```

`runs/network` installs the rest, including `network-manager-gnome`. The i3
config had been exec'ing `nm-applet` since it was written while nothing
installed it, so the tray icon never appeared — and without its secret agent a
VPN connect fails with nothing on screen to say why.

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
- waybar's network module is display-only; the workstation is on ethernet. The
  i3 laptop has `launch-wifi`, but hypr has no equivalent binding yet - the
  launchers there would need `launch-wifi`/`launch-vpn` copies in env-hypr, or
  the four one-line wrappers moved to env-common with only `launch-tui` and
  `launch-or-focus-tui` staying per-profile.
- `runs/tui` builds `wiremix` and `bluetui` from crates.io. The Ubuntu build
  deps (`libpipewire-0.3-dev`, `libclang-dev`) have not been exercised in a
  dev-vm guest yet, unlike the rest of the apt names.
- `runs/hyprland`, `runs/nvim` and the copr path in `runs/ghostty` need sudo and
  have not been run end to end yet - only `runs/tui` and `runs/fonts` have.
- `env-common/.local/scripts/misc/tmux-sessionizer` is the old homegrown sessionizer,
  superseded by the vendored one but kept for reference.
