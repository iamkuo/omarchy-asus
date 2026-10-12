# omarchy-asus

A tabbed ASUS laptop control panel for the [Omarchy](https://omarchy.org) bar,
built on [`asusctl`](https://asus-linux.org/). Power profiles, keyboard RGB,
editable fan curves, and firmware limits — organized like
[G-Helper](https://github.com/seerge/g-helper), scoped to what your specific
model actually supports.

| Main | RGB |
|---|---|
| ![Main tab](docs/screenshots/main.png) | ![RGB tab](docs/screenshots/rgb.png) |

| Fan | Advanced |
|---|---|
| ![Fan tab](docs/screenshots/fan.png) | ![Advanced tab](docs/screenshots/advanced.png) |

## Why

The stock single-scroll ASUS panel dumps every `asusctl` feature into one
column regardless of whether your laptop supports it — wattage sliders with
no context, keyboard RGB effects that silently no-op on unsupported hardware,
a fan curve toggle for the master enable that never appears in the UI. This
plugin detects what your specific model reports supporting and only shows
that.

## Features

- **Live sensors** — CPU and GPU temperature, both fan speeds, GPU draw and
  utilisation, battery charge and charge rate, refreshed every 2 seconds while
  the panel is open. The same readings appear in the bar icon's tooltip, so
  "how hot is it right now" needs no click.
- **Main** — performance mode (Quiet/Balanced/Performance, tinted by mode),
  saved separately for AC and battery, plus GPU mode (Eco/Standard/Ultimate),
  screen refresh rate and panel overdrive,
  battery charge limit, and a one-shot charge to any level you pick: the panel
  caps charging at the target and restores your limit once the battery reaches
  it. While it runs the button becomes **Stop**, which restores the limit
  immediately. (asusd's own one-shot always charges to 100% — its percent only
  sets the limit to restore — so charging to an arbitrary level is handled by
  the panel.)
- **RGB** — keyboard lighting, filtered to the aura effects your laptop
  actually reports (`asusctl info --show-supported`), not a fixed list of
  twelve, plus brightness and the awake/boot/sleep power states. On 2021+
  keyboards the power states come from the newer per-zone
  `asusctl aura power <zone>` API, adding a shutdown state and covering every
  zone the laptop reports (logo, lightbar, lid, rear glow); zones your model
  does not have never appear.
- **Fan** — a master "Custom Fan Curves" switch, a per-profile curve editor
  (curves are stored per power profile, so you pick which profile you are
  tuning), draggable curves per fan (CPU/GPU, plus Mid on laptops with a third
  fan) with the live RPM and temperature for that fan alongside, and a
  one-click reset.
- **Advanced** — firmware power limits (PL1/PL2/PL3-FPPT, GPU dynamic boost,
  GPU temp target) with ranges read from the firmware and a "Defaults" button
  that replays the values `asusctl` reports as default. Each control appears
  only if `asusctl armoury list` says your laptop exposes it. Note that PPT
  limits are only applied by the firmware while profile tuning is enabled
  (`asusctl profile tuning true`); asusd stores the values either way.
- **CPU boost** (Advanced) — a Turbo Boost on/off switch, the one thermal lever
  `asusctl` does not expose: it writes `intel_pstate/no_turbo` on Intel and
  `cpufreq/boost` on AMD, plus a per-mode plan (Quiet/Balanced/Performance) that
  applies when you switch modes, the way G-Helper stores it. Both files are
  root-owned, so the switch needs the one-time [polkit rule](#privileges);
  without it you get a password prompt per change, and cancelling leaves the
  setting alone and says so. The section hides itself on a laptop that exposes
  neither file.
- **Services** (Advanced) — `asusd`, `supergfxd` and `nvidia-powerd` with their
  current state, since a stopped daemon is the usual reason a control in this
  panel does nothing. `nvidia-powerd` also gets an enable/disable switch, shown
  only where the unit is actually installed, and a unit that is not installed at
  all gets an Install button that adds its package and enables it
  ([details](#installing-missing-daemons)).
- **Bar icon** — scroll over it to cycle performance modes without opening the
  panel.

### G-Helper parity

This mirrors [G-Helper](https://github.com/seerge/g-helper)'s layout and
feature set where Linux tooling allows it. Where it does not:

| G-Helper feature | Status here |
|---|---|
| Anime Matrix / Slash display | Not implemented (no such hardware to test against) |
| CPU boost toggle | Implemented on Advanced — writes `intel_pstate/no_turbo` (Intel) or `cpufreq/boost` (AMD) through `pkexec`, so it needs the one-time polkit rule in [Privileges](#privileges) |
| AutoTDP, FPS limiter, overlay | Windows-only mechanisms |
| Per-key / per-zone RGB | `asusctl` exposes zones only on some models; single-colour effects only for now |
| Automatic AC/battery profile switching | `asusd` stores separate performance profiles and reapplies them when power changes |

### Performance profiles

Selecting Quiet, Balanced, or Performance saves the choice for the current
power source using `asusctl profile set --ac` or `--battery`. The other
power source keeps its saved choice. `asusd` handles applying these profiles
when the charger is connected or disconnected. Scrolling the bar icon uses
the same behavior.

If you would rather pin the mode yourself, use the **Auto-switch on power**
section on the Main tab: choose a performance mode for "Plugged in" and for
"On battery", and the panel applies it when the charger changes. These are
stored as the `defaultProfileAc` and `defaultProfileBattery` plugin settings
(`Auto`, `Quiet`, `Balanced`, `Performance`); `Auto` leaves asusd's saved
profile in charge. Plug/unplug sets only the mode — it has no refresh setting
of its own.

### Screen refresh per mode

Each performance mode carries its own default refresh rate (**SCREEN PER MODE**
on the Main tab). Switching to a mode applies that mode's rate, so the screen
follows the mode. Stored as `refreshQuiet`/`refreshBalanced`/`refreshPerformance`
(`Auto`, or one of the Hz values the internal panel offers). Since plug/unplug
just switches the mode, it applies that mode's rate too.

### CPU boost per mode

Each performance mode also carries its own CPU boost setting, the way G-Helper
stores it (**CPU BOOST** on the Advanced tab). Switching to a mode applies that
mode's setting, so boost follows the mode — including when the switch comes from
plugging or unplugging the charger, or from scrolling the bar icon. Stored as
`boostQuiet`/`boostBalanced`/`boostPerformance` (`Auto`, `On`, `Off`); `Auto`
leaves boost as it is, so a mode that does not care about boost never fights the
toggle above it.

The flag has to be read before it can be written, since the CPU vendor decides
both the path and the polarity (`no_turbo` is inverted against `cpufreq/boost`),
so a mode switch made from the bar with the panel closed parks that mode and
applies it as soon as the first probe lands.

### Installing missing daemons

A unit that is genuinely not installed — as opposed to one that is installed but
stopped, or a probe that has not answered yet — gets an **Install** button next to
its state. The button opens a terminal through Omarchy's own
`omarchy-launch-tui` and runs:

| Unit | Package | What runs |
|---|---|---|
| `asusd.service` | `asusctl` | `omarchy-pkg-add asusctl && sudo systemctl enable --now asusd.service` |
| `supergfxd.service` | `supergfxctl` | `omarchy-pkg-aur-add supergfxctl && sudo systemctl enable --now supergfxd.service` |
| `nvidia-powerd.service` | `nvidia-utils` | `omarchy-pkg-add nvidia-utils && sudo systemctl enable --now nvidia-powerd.service` |

`asusctl` is what Omarchy's own installer adds for ROG hardware, so it goes
through the repo adder; `supergfxctl` is AUR-only there and goes through yay. The
terminal stays open with Omarchy's done prompt so the result is readable, and the
panel picks the new state up on its next refresh.

The NVIDIA row is only offered on a laptop whose firmware reports the NVIDIA
attributes this panel already reads (`nv_temp_target` / `nv_dynamic_boost`), since
that package is the driver itself and there is no reason to pull it onto an
AMD-only machine.

None of this goes through `pkexec`: pacman has to prompt for your password
itself, and you should see what it does. If the terminal cannot be opened at all
(no `omarchy-launch-tui`), the panel says so and prints the command to run by
hand.

### Screen refresh rate

`asusctl` has no display controls, so the refresh buttons drive Hyprland
directly. The built-in `eDP-*` panel is preferred over external monitors, since
this is a laptop-screen feature.

Two details worth knowing:

- Hyprland 0.56 parses its config as Lua, and `hyprctl keyword monitor` is
  rejected against a non-legacy parser. The mode change goes through
  `hyprctl eval "hl.monitor({ ... })"` instead — the same call
  `omarchy-hyprland-monitor-scaling` uses. Position and scale are always
  repeated, because `hl.monitor` replaces the whole rule.
- If [hyprmoncfg](https://github.com/crmne/hyprmoncfg) is installed and its
  daemon is running, it owns monitor configuration and re-applies its active
  saved profile a few seconds after any runtime change — a plain `hl.monitor`
  call silently reverts. The plugin detects this (`hyprmoncfg status --json`)
  and follows the mode change with `hyprmoncfg save <active profile>` so it
  sticks and survives a reboot. The Screen header shows the profile name when
  this is in effect.

  Note that `hyprmoncfg save` snapshots the *whole* current monitor state, not
  just the refresh rate, so it also refreshes that profile's workspace-to-output
  assignments. Without the daemon, the runtime change stands on its own and
  lasts until the Hyprland config is reloaded.

## Development

```bash
node test-model.js   # parser regression checks against real asusctl output
```

## Prerequisites

```bash
# From AUR
yay -S asusctl

# Or from the OGC Arch repo — see https://asus-linux.org for setup
sudo pacman -S asusctl

sudo systemctl enable --now asusd.service
```

## Install

```bash
omarchy plugin add https://github.com/iamkuo/omarchy-asus.git --enable
```

Or clone manually into `~/.config/omarchy/plugins/io.github.moneytosms.asus`
and enable it via the Omarchy plugin menu.

## Remove

```bash
omarchy plugin remove io.github.moneytosms.asus
```

Nothing is written outside the plugin folder and the plugin's own settings
block in `~/.config/omarchy/shell.json`, which Omarchy drops with the plugin.

## Configuration

`~/.config/omarchy/shell.json`, under the plugin's settings:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `showBatteryLimit` | boolean | `true` | Show the battery charge limit section on Main |
| `refreshIntervalSec` | integer | `10` | Poll interval while the panel is open (5–60s) |
| `defaultProfileAc` | enum | `Auto` | Profile to apply automatically when AC power is connected (`Auto`, `Quiet`, `Balanced`, `Performance`). `Auto` leaves asusd's saved AC profile in charge |
| `defaultProfileBattery` | enum | `Auto` | Profile to apply automatically when the charger is unplugged. `Auto` leaves asusd's saved battery profile in charge |
| `refreshQuiet` | string | `Auto` | Refresh rate to apply when switching to Quiet (`Auto`, or a Hz value the internal panel offers) |
| `refreshBalanced` | string | `Auto` | Refresh rate to apply when switching to Balanced |
| `refreshPerformance` | string | `Auto` | Refresh rate to apply when switching to Performance |
| `boostQuiet` | enum | `Auto` | CPU boost to apply when switching to Quiet (`Auto`, `On`, `Off`) |
| `boostBalanced` | enum | `Auto` | CPU boost to apply when switching to Balanced |
| `boostPerformance` | enum | `Auto` | CPU boost to apply when switching to Performance |

## Privileges

Everything in this plugin works without root except the CPU boost switch and the
`nvidia-powerd` toggle, and both are optional: without any of the rules below the
plugin still works, you just authenticate per change, and a cancelled prompt
leaves the setting untouched and reports it.

**CPU boost.** `intel_pstate/no_turbo` and `cpufreq/boost` are root-owned and
`asusctl` has no equivalent, so the switch runs `pkexec tee <path>`. To avoid a
prompt on every click, scope a rule to exactly those two paths:

```bash
sudo tee /etc/polkit-1/rules.d/60-asus-turbo.rules > /dev/null <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "/usr/bin/tee" &&
        /intel_pstate\/no_turbo|cpufreq\/boost/.test(action.lookup("command_line")) &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF
```

Change the group (`wheel`, `sudo`, …) to match your system.

**nvidia-powerd.** The switch runs
`pkexec systemctl enable|disable --now nvidia-powerd.service`, which needs two
separate systemd polkit actions — and only the first of them can be scoped to a
single unit:

```bash
sudo tee /etc/polkit-1/rules.d/61-asus-powerd.rules > /dev/null <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "nvidia-powerd.service" &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF
```

That rule covers the start/stop half. The enable/disable half needs
`org.freedesktop.systemd1.manage-unit-files`, which systemd does not pass a unit
name to (see [systemd#38992](https://github.com/systemd/systemd/issues/38992)),
so a rule for it would grant the group the right to enable or disable *any*
unit. This plugin deliberately does not ask you to grant that, which means the
switch still shows one prompt per change — answer it, or if you want
`nvidia-powerd` off for good, run
`sudo systemctl disable --now nvidia-powerd.service` once and leave the switch
alone.

## Compatibility

Works with any laptop `asusctl` supports (ROG, TUF, ProArt, Zenbook). Every
section — RGB effects, fan curves, individual firmware attributes — is gated
on what `asusctl` reports for your specific model; unsupported controls don't
appear rather than sitting there doing nothing.

## Troubleshooting

```bash
# Verify the plugin is detected
omarchy plugin validate ~/.config/omarchy/plugins/io.github.moneytosms.asus

# Check asusd is running
systemctl status asusd

# Check what your model supports
asusctl info --show-supported
asusctl armoury list

# Check the daemons the panel's controls depend on (also shown on Advanced)
systemctl is-active asusd supergfxd nvidia-powerd

# Check the boost switch the CPU boost row drives
cat /sys/devices/system/cpu/intel_pstate/no_turbo   # or cpufreq/boost on AMD
```

## License

MIT
