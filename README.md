# dev

Machine setup: dotfiles plus the installers that provision them. Replaces the
old `.dotfiles` repo.

Targets two machines:

| Machine | Distro | Session |
| --- | --- | --- |
| Workstation | Fedora | i3 (X11), with Hyprland (Wayland) still installed |
| Work laptop | Ubuntu | i3 (X11) |

The workstation has both sessions provisioned and picks one at the gdm login
screen; the stow profile decides which set of configs is linked, so switching
is `./dev-env profile <hypr\|i3> && ./dev-env link`, then log out and back in.

## Layout

```
dev-env              orchestrator: link dotfiles, run installers
lib/platform.sh      distro detection + per-distro package name map
runs/                one installer per tool
runs/env             machine-wide environment variables (/etc/environment)
env-common/          dotfiles for every machine
env-hypr/            Hyprland session: compositor, waybar, launch-* scripts
env-i3/              i3 session: i3, i3status, .xprofile
secrets/             age-encrypted secrets
resources/           vendored third-party tools (submodule)
```

Each `env-*` is a literal `$HOME` mirror, so linking is just `stow`. A file at
`env-common/.config/tmux/tmux.conf` lands at `~/.config/tmux/tmux.conf`.

## Profiles

`env-common` is stowed everywhere; exactly one session profile joins it. A
machine running i3 on X11 must not receive Hyprland configs or the `launch-*`
scripts, all of which shell out to `hyprctl` or `uwsm-app` and would fail there
— so on the workstation, where both sessions are installed, the profile has to
be pinned rather than detected.

```sh
./dev-env profile            # what this machine resolved to
./dev-env profile i3         # pin it (writes .dev-profile, untracked)
```

Detection order: `$DEV_ENV_PROFILE`, then `.dev-profile`, then whichever of
`hyprctl` / `i3` is installed. On a bare machine neither exists yet, so `link`
stows `env-common` only — re-run it after `runs/desktop`. The fallback checks
`hyprctl` first, so a machine with both installed resolves to `hypr` until
`.dev-profile` says otherwise.

### zsh

`env-common/.zshenv` is the one zsh file that has to sit at `$HOME` — it is read
first and is the only place `ZDOTDIR` can be set. It points `ZDOTDIR` at
`~/.config/zsh`, so everything else lives in `env-common/.config/zsh/`. That also
keeps oh-my-zsh's `.zcompdump` caches out of `$HOME`.

Consequence worth remembering: with `ZDOTDIR` set, a `~/.zshrc` is **ignored
entirely**. If zsh ever seems to load the wrong config, check `echo $ZDOTDIR`
first.

### Dark mode and theming

On a machine with no desktop environment, dark mode is not one setting — every
toolkit asks somewhere different, and the pieces fail independently, which is
why it can look half-applied:

| What reads it | Where it looks | Kept in |
| --- | --- | --- |
| Firefox, Chromium, Electron, GTK4/libadwaita, nvim's `auto-dark-mode` | the **Settings portal** (`org.freedesktop.appearance color-scheme`) | dconf — applied by `runs/theme` |
| GTK3 and GTK4 | `GTK_THEME=Adwaita:dark` | **system variable** — `runs/env` |
| Qt 6 | `QT_QPA_PLATFORMTHEME`, `QT_STYLE_OVERRIDE` → `~/.config/qt6ct`, drawn by Kvantum's `KvGnomeDark` | **system variable** + `env-common` |
| GTK3/GTK4, where no variable is set | `~/.config/gtk-{3,4}.0/settings.ini` | `env-common` |

#### System variables

The theme variables are machine defaults, so they are set machine-wide rather
than in a login shell — a login shell is the one context that is *not* a
desktop, and a gdm session, a systemd user service and anything D-Bus activates
all read none of it. `runs/env` owns one list and writes it to both files that
carry system variables, because they cover different processes:

| File | Read by | Covers |
| --- | --- | --- |
| `/etc/environment` | `pam_env`, at login | the session and everything descended from it: gdm's X session, i3, everything i3 spawns |
| `/etc/environment.d/90-dev-env.conf` | the systemd user manager | user services and D-Bus activated programs — `xdg-desktop-portal` and its backends among them |

Both are root-owned and outside stow, like the logind lid drop-in, so `link`
cannot restore them and `doctor` checks them instead. `/etc/environment` is not
ours alone — Ubuntu ships a `PATH` in it — so the installer rewrites only its
own delimited block. **They are read at login**, so nothing already running
picks up a change; `doctor` reports the file and the running session separately
for exactly that reason.

`GTK_THEME` is the floor, not the whole story: libadwaita apps ignore it and
follow the portal, which is why the dconf key stays the primary setting.

The portal row is the one that matters and the one that was broken. Under GNOME
the settings daemon pushes the dconf key into XSettings and every app picks it
up; under i3 nothing does, so GTK3 needs `settings.ini` — but the *portal* is
what the browsers and Electron apps ask, and it was not running at all:

- `xdg-desktop-portal.service` is `Requisite=graphical-session.target`, and
  nothing under a bare i3 ever reaches that target — `gnome-session` does it
  under GNOME, `uwsm` under Hyprland. `env-i3/.config/systemd/user/i3-session.target`
  is what the i3 config starts to bring it up, in the same `exec_always` that
  hands `DISPLAY`, `XAUTHORITY` and `XDG_CURRENT_DESKTOP` to the user manager
  and the D-Bus activation environment.
- This box has the gnome, gtk and hyprland portal backends installed and none
  of them claims i3, so `env-i3/.config/xdg-desktop-portal/i3-portals.conf`
  names `gtk` — the only backend that reads the colour scheme out of dconf.
  It is `i3-portals.conf`, not `portals.conf`, so the Hyprland session keeps
  its own backend for screencast.

`doctor` checks both halves separately, because the key can be right while the
portal is dead and every browser still renders light:

```sh
  ok    color scheme: prefer-dark
  ok    settings portal reports: dark
```

To flip the machine to light, both halves move together — the dconf key and the
two `settings.ini` files:

```sh
gsettings set org.gnome.desktop.interface color-scheme prefer-light
```

GTK2 is deliberately not covered: dark GTK2 needs a whole theme package
(`gnome-themes-extra`) for a toolkit nothing here still uses.

### Displays (i3)

The laptop lives on an external monitor with the lid shut, and only opens for
meetings, so the lid is the switch that picks the layout (on a machine with no
lid, such as the workstation, `monitor` just enables every connected output
left to right and `runs/i3` skips the logind drop-in below):

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

### Locking (i3)

One locker, three ways into it, all through `xss-lock`:

| Trigger | Path |
| --- | --- |
| `$mod+Ctrl+l` | `loginctl lock-session` → logind's `Lock` signal → `xss-lock` |
| 10 minutes idle | X screensaver timer (`xset s 600 600`) → `xss-lock` |
| suspend (incl. the laptop's lid) | logind's `PrepareForSleep` → `xss-lock` |

`xss-lock` is what makes one `i3lock` serve all three, so there is a single
locker to configure rather than three. Two flags are load-bearing:
`--transfer-sleep-lock` hands `i3lock` logind's inhibitor fd so the lock is up
*before* the machine suspends rather than racing it, and `i3lock -n` (nofork) is
required because `xss-lock` tracks the locker as its own child — a locker that
forks away looks like it exited immediately, and `xss-lock` would treat the
screen as unlocked while `i3lock` is still up.

`doctor` checks that `xss-lock` is running *and* that the screensaver timeout is
non-zero, because those fail apart: with `xset` missing the process runs happily
and simply never fires on idle, and a lock that silently never happens is the
worst way for one to fail.

**Idle locks; it never suspends.** Three separate things had to agree on that,
and they are checked separately because they drift apart:

| Mechanism | Setting | Effect |
| --- | --- | --- |
| `xss-lock` + X screensaver | `xset s 600 600` | locks after 10 min |
| DPMS | `xset dpms 0 0 900` | powers the **monitor** down after 15 min — display power, not system sleep |
| logind | `IdleAction=ignore` (`/etc/systemd/logind.conf.d/20-idle.conf`) | logind takes no idle action of its own |

`ignore` is already systemd's default, so the drop-in changes nothing today —
it is written down because a default is not a promise, and a machine that
sleeps while you read looks like a hardware fault rather than a setting.
`doctor` asserts the value logind is actually running with, not the file.

GNOME's `sleep-inactive-ac-type` was still set to `suspend`; `gsd-power` never
runs in an i3 session so it bit nothing, but it would have taken the machine
down the first time anyone logged into GNOME. `runs/i3` sets it to `nothing`.
The battery equivalent is deliberately left alone — a laptop that sleeps on
battery is behaving correctly.

Suspend itself still locks first, and the laptop's lid still suspends: closing
a lid is a deliberate act, and `--transfer-sleep-lock` means the lock is up
before the machine goes down.

**Gotcha worth keeping:** i3 re-runs `exec_always` on **restart**
(`$mod+Ctrl+r`), not on **reload** (`$mod+Shift+c`). A reload re-reads the
config and updates bindings, so it looks like it worked, while every autostart
in the file is untouched. Every `exec_always` in this config — the locker, the
session target, the monitor scripts — needs a restart to take effect.

Ubuntu: `i3lock`, `xss-lock` and `x11-xserver-utils` (which carries both `xset`
and `xrandr`) are all in noble's universe, and noble's `i3lock` ships
`/etc/pam.d/i3lock` — without that PAM file the lock screen would accept no
password at all.

### Screenshots (i3)

`CTRL+SHIFT+P` runs `flameshot gui -c`. On Fedora that hung for 30 seconds and
then failed with "Unable to capture screen", while the same binding worked on
the laptop — flameshot 14 asks the **freedesktop screenshot portal** even on
X11, and flameshot 12, which Ubuntu ships, captures X11 natively.

No portal backend can screenshot an i3 session: the gtk backend answers by
calling `org.gnome.Shell.Screenshot`, which does not exist outside GNOME, and
the hyprland one needs Hyprland. So there are two halves to this:

- `runs/i3` sets `useX11LegacyScreenshot=true` in `~/.config/flameshot/flameshot.ini`,
  flameshot's own escape hatch — its help text names i3 as the case it is for.
  Not stowed: flameshot rewrites that file through QSettings, which replaces it
  and would leave a symlink dangling the first time any other setting changed.
  `doctor` checks the key instead.
- `i3-portals.conf` sets `org.freedesktop.impl.portal.Screenshot=none`, so
  anything *else* that asks the portal for a screenshot gets an immediate "no
  implementation" rather than a 30-second hang on a service that will never
  answer.

Flameshot warns that a future version may drop the legacy X11 path. If that
lands before this machine moves to Wayland, the replacement is a different tool
(`maim`, `scrot`), not a different flameshot setting.

### System TUIs (i3)

Audio, wifi, VPN and bluetooth are all TUIs in a floating terminal, the same
tools the workstation uses so the habits carry across:

| Key | Tool | What |
| --- | --- | --- |
| `$mod+Shift+a` | `wiremix` | audio devices and volume (PipeWire) |
| `$mod+Shift+n` | `wlctl` | wifi, and WireGuard profiles |
| `$mod+Ctrl+v` | `nmcli` + rofi | VPN up/down (not `$mod+Shift+v`, which splits) |
| `$mod+b` | `bluetui` | bluetooth |

`launch-tui` spawns them and `launch-or-focus-tui` focuses an already-open one,
so a second keypress does not stack up windows. Both are i3-specific: the
env-hypr twins go through `uwsm-app` and `xdg-terminal-exec`, which are
Wayland-only. Ghostty fills X11's two `WM_CLASS` fields from separate options —
`--class` and `--x11-instance-name` — and `launch-tui` sets both to
`zepzeper.<tool>`, which is what the `for_window` float rule matches and what
keeps the ids identical to the hypr window rules.

Wifi is `wlctl`, and the detour is worth recording. Omarchy — which this config
descends from, hence `launch-or-focus`'s usage string — uses `impala`, and
`impala` is the better-looking tool. It drives **iwd**, which is no use here:
both the wifi and the OpenVPN profile live in **NetworkManager**, and iwd cannot
do the 802.1X a work network may ask for. impala's maintainer turned down a
NetworkManager backend as too complex, so `wlctl` exists to be exactly that.
`nmtui` was the stopgap before it and is a newt dialog that no theme can reach.

**wlctl does not connect the OpenVPN profile**, and this is by its design rather
than a fault: its README says OpenVPN "requires external `nmcli` command, not
handled directly by wlctl". Its VPN pane lists the profile and toggles
autoconnect, but pressing enter will not bring it up — WireGuard is the type it
drives natively. The [open request for real VPN
management](https://github.com/aashish-thapa/wlctl/issues/63) has no maintainer
response. So the split is: `wlctl` for wifi, `$mod+Ctrl+v` for the VPN.

`wlctl` is young — 0.1.x, GPLv3 — so if it disappoints, `launch-wifi` is a
two-line revert to `nmtui connect`.

Both `wlctl` and the VPN toggle need a **polkit authentication agent**, which
GNOME's session starts and a bare i3 session does not. Without one, anything
needing admin authorisation — deleting a saved profile, say — fails with no
dialog and no visible reason, exactly like the VPN password below. `runs/i3`
installs one and the i3 config execs whichever is present: Fedora retired
`polkit-gnome`, so there it is `mate-polkit` — the same GTK3 agent, without any
MATE desktop behind it — while Ubuntu still has `polkit-gnome`. `doctor` fails
if neither binary is on the machine.

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

or, for a certificate-only server, by pointing a new connection at the files.
The usual handout is four of them, and each maps to one `vpn.data` key:

| File | Key | |
| --- | --- | --- |
| `ca.crt` | `ca` | the CA to trust |
| `user.crt` | `cert` | client certificate |
| `user.key` | `key` | client private key |
| `ta.key` | `ta` **or** `tls-crypt` | see below |

```sh
mkdir -p ~/.cert/nm-openvpn && chmod 700 ~/.cert/nm-openvpn
cp ca.crt user.crt user.key ta.key ~/.cert/nm-openvpn/
chmod 600 ~/.cert/nm-openvpn/user.key ~/.cert/nm-openvpn/ta.key

nmcli connection add type vpn vpn-type openvpn con-name work-vpn ifname '*'
nmcli connection modify work-vpn vpn.data \
  'connection-type=tls, remote=vpn.example.com, port=1194, ca=/home/zepzeper/.cert/nm-openvpn/ca.crt, cert=/home/zepzeper/.cert/nm-openvpn/user.crt, key=/home/zepzeper/.cert/nm-openvpn/user.key, ta=/home/zepzeper/.cert/nm-openvpn/ta.key, ta-dir=1'
```

Paths in `vpn.data` must be absolute — `~` is not expanded. Modifying an
existing connection is safer one key at a time (`+vpn.data ca=...`), since
passing `vpn.data` whole replaces the dict and drops the `remote` with it.

`connection-type` is the setting to get right, and the failure is confusing when
it is wrong. `tls` is certificates only — no username, no password, nothing to
store. `password` and `password-tls` additionally demand an `auth-user-pass`
credential, and a connection wrongly set to either will ask for a
`vpn.secrets.password` that was never issued. If the handout was four files and
no password, the type is `tls`, and any leftover `username` should be cleared
with `-vpn.data username`.

`ta.key` is the other trap: tls-auth and tls-crypt keys are byte-identical on
disk (both `BEGIN OpenVPN Static key V1`), so only the server config says which
is in use. `tls-auth ta.key 0` there means `ta=` plus `ta-dir=1` here;
`tls-crypt ta.key` means `tls-crypt=` and no direction. Guessing wrong shows up
in `journalctl -u NetworkManager -f` as a TLS handshake or decrypt error rather
than anything about the key.

#### The password has to be system-owned

Only relevant when `connection-type` is `password` or `password-tls`. A
certificate-only `tls` connection has no password at all, and a request for one
means the type is wrong rather than the secret missing — see above.

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
nmcli --ask connection up id <NAME>
```

`--ask` prompts on the terminal, and with the flag now `0` NetworkManager keeps
the secret it was handed, so later connects need no prompt. It also keeps the
password out of both the shell history and the process list — worth preferring
over passing `password=` as an argument, which is visible in `ps` for as long as
`nmcli` runs.

To set it without connecting, note that **the prompt is shell-specific**: the
login shell here is zsh, where `read -p` means "read from a coprocess" and fails
with `read: -p: no coprocess`. The prompt goes inside the parameter instead:

```zsh
read -rs "p?VPN password: "; echo         # zsh
nmcli connection modify <NAME> +vpn.secrets "password=$p"; unset p
```

```bash
read -rs -p 'VPN password: ' p            # bash
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

### Which terminal a TUI opens in (hypr)

env-hypr's `launch-tui` never names a terminal. It calls `xdg-terminal-exec`,
which reads the chosen terminal's desktop entry to learn *that terminal's*
spelling of the flags — ghostty declares `X-TerminalArgAppId=--class=`, kitty
declares `--class` — so one `--app-id=zepzeper.<tool>` keeps working whatever
the terminal is.

The choice comes from `~/.config/xdg-terminals.list`, and with no such file
`xdg-terminal-exec` falls back to scanning desktop entries for
`Categories=TerminalEmulator` and taking the first hit. On a machine that also
has kitty installed kitty won that scan, so `$mod+Shift+t` opened btop in kitty
— working keybinding, wrong terminal, and none of env-common's ghostty config
applying. `env-common/.config/xdg-terminals.list` pins the order:

```
com.mitchellh.ghostty.desktop
kitty.desktop
```

Confirm with `xdg-terminal-exec --print-id`, which resolves the choice without
launching anything. `doctor` runs that same check on the hypr profile, because
this is drift a *newly installed* package causes — nothing in the repo changes,
and the keybinding keeps working, so nothing else would report it.

### hyprctl after the Lua config (hypr)

Hyprland 0.56 configures in Lua, and `hyprctl` followed: `dispatch` now parses
its arguments as Lua rather than as the old `focuswindow address:0x...`
strings, and `keyword` is gone entirely (`keyword can't work with non-legacy
parsers. Use eval.`). Both failures land on stderr, and none of these scripts
read stderr, so three bindings had quietly stopped doing anything:

| Script | Binding | Was |
| --- | --- | --- |
| `launch-or-focus` | `SUPER+Shift+m`, and every `launch-or-focus-tui` | `dispatch focuswindow address:…` |
| `launch-window-pop` | `SUPER+o` | `dispatch togglefloating/resizeactive/moveactive/centerwindow/pin/alterzorder/tagwindow` |
| `launch-workspace-toggle` | `ALT+s` | `keyword workspace "N, layout:…"` |

All three now go through `hyprctl eval`, which takes statements rather than a
single expression. The shape that matters: `hl.dsp.*` builds a *descriptor*,
and `hl.dispatch()` is what runs it — `hyprctl eval 'hl.dsp.window.close()'`
type-checks, returns `ok`, and does nothing at all. Targeting is by window
object, not address, so the address goes through
`hl.get_window("address:0x…")` first; the `address:` prefix is required, a bare
`0x…` returns nil. `hyprctl clients -j` and friends are unaffected, so the jq
lookups stayed.

`/usr/share/hypr/stubs/hl.meta.lua` is the generated type stub for the whole
API and is the only real reference for what exists — it types dispatcher
arguments as `fun(...)`, though, so the argument *names*
(`{ window = w, tag = "+pop" }`) came from trying them against a scratch
window.

Two things fell out of the port. `launch-window-pop` validates its geometry
arguments now, because they are interpolated into generated Lua rather than
into a dispatcher string. And `launch-workspace-toggle` lost its state file:
it recorded which workspaces were scrolling in `/tmp/hypr/workspace-layouts.conf`
because `keyword` could write config but never read it back — except nothing
creates `/tmp/hypr`, so the file was never written, `grep -q` on it was false
every time, and the toggle only ever went one way. `hyprctl activeworkspace -j`
reports the live `tiledLayout`, so there is nothing left to remember.

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
- on hypr, `xdg-terminal-exec` still resolves to ghostty — installing another
  terminal can silently take that over

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
  i3 laptop has `launch-wifi` and `launch-vpn`, but hypr has no equivalent
  binding yet - the
  launchers there would need `launch-wifi`/`launch-vpn` copies in env-hypr, or
  the four one-line wrappers moved to env-common with only `launch-tui` and
  `launch-or-focus-tui` staying per-profile.
- `runs/tui` builds `wiremix`, `bluetui` and `wlctl` from crates.io. The Ubuntu
  build deps (`libpipewire-0.3-dev`, `libclang-dev`) have not been exercised in
  a dev-vm guest yet, unlike the rest of the apt names.
- rofi has no theme in this repo, so `launch-menu`, `$mod+d` and the VPN picker
  all render in rofi's stock look while ghostty is on Rose Pine Moon
  (`#161521`). A `.rasi` matching it would fix all three at once.
- `runs/hyprland`, `runs/nvim` and the copr path in `runs/ghostty` need sudo and
  have not been run end to end yet - only `runs/tui` and `runs/fonts` have.
- `env-common/.local/scripts/misc/tmux-sessionizer` is the old homegrown sessionizer,
  superseded by the vendored one but kept for reference.
