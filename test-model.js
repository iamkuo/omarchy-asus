// Regression checks for Model.js — run with `node test-model.js`.
//
// Model.js is plain ES5 loaded by QML, so it can be evaluated directly here.
// The fixtures are verbatim output from asusctl 6.3.8 / hyprctl / the sensor
// script on a TUF Gaming F15 (FX507VV); every parser in Model.js reads real
// tool output, so the only useful test is against real tool output.

const fs = require("fs")
const vm = require("vm")
const assert = require("assert")
const path = require("path")

const M = {}
vm.createContext(M)
vm.runInContext(fs.readFileSync(path.join(__dirname, "Model.js"), "utf8"), M)

// Store profile changes for the power source currently in use.
assert.deepEqual(M.profileCommand("Performance", false), ["asusctl", "profile", "set", "--ac", "Performance"])
assert.deepEqual(M.profileCommand("Quiet", true), ["asusctl", "profile", "set", "--battery", "Quiet"])

// ---------------------------------------------------------------- battery
assert.deepEqual(M.parseBatteryInfo("Current battery charge limit: 80%"), { limit: 80 })

// One-shot plan: persisted as JSON and validated on read.
assert.deepEqual(M.oneshotState('{"target":90,"restore":80}'), { target: 90, restore: 80 })
assert.equal(M.oneshotStateJson({ target: 90, restore: 80 }), '{"target":90,"restore":80}')
assert.equal(M.oneshotState(""), null)
assert.equal(M.oneshotState("not json"), null)
assert.equal(M.oneshotState('{"target":150,"restore":80}'), null)  // out of range
assert.equal(M.oneshotState('{"target":90}'), null)                // restore missing

// ---------------------------------------------------------------- armoury
const ARMOURY = `Multiple asusd interfaces devices found
charge_mode:
  current: [0,1,2]

dgpu_disable:
  current: [(0),1]

gpu_mux_mode:
  current: [(0),1]

nv_dynamic_boost:
  current: 5..[25]..25
  default: 25

nv_temp_target:
  current: 75..[87]..87
  default: 87

panel_overdrive:
  current: [(0),1]

ppt_pl1_spl:
  current: 28..[133]..135
  default: 115

ppt_pl2_sppt:
  current: 28..[135]..135
  default: 135

ppt_pl3_fppt:
  current: 35..[80]..80
  default: 80
`

const a = M.parseArmoury(ARMOURY)
assert.equal(a.supported.pptPl1, true)
assert.equal(a.supported.pptPl3, true)
assert.equal(a.supported.nvTempTarget, true)
assert.equal(a.supported.panelOverdrive, true)
assert.equal(a.values.ppt_pl1_spl, 133)
assert.deepEqual(a.ranges.ppt_pl1_spl, { min: 28, max: 135 })
assert.equal(a.defaults.ppt_pl1_spl, 115)
assert.equal(a.values.ppt_pl3_fppt, 80)
assert.equal(a.defaults.ppt_pl3_fppt, 80)
assert.equal(a.values.gpu_mux_mode, 0)
// "Multiple asusd interfaces devices found" must not be read as an attribute.
assert.equal(a.supported["Multiple asusd interfaces devices found"], undefined)

// The current option is whichever one is parenthesised — matching only the
// first entry made every toggle read as "off" no matter its real state.
assert.equal(M.parseArmouryValue("[(0),1]").value, 0)
assert.equal(M.parseArmouryValue("[0,(1)]").value, 1)
assert.equal(M.parseArmouryValue("[0,1,2]"), null)

// ---------------------------------------------------------------- sensors
const SENSORS = `cpu_temp=63000
fan_cpu=3000
fan_gpu=3100
bat_pct=99
bat_status=Charging
bat_power=8627000
gpu_temp=51
gpu_power=6.66
gpu_util=15
gpu_runtime=active
`
const s = M.parseSensors(SENSORS)
assert.equal(s.cpuTemp, 63)      // millidegrees -> C
assert.equal(s.fanCpu, 3000)
assert.equal(s.gpuTemp, 51)
assert.equal(s.gpuPower, 7)
assert.equal(s.gpuRuntime, "active")
assert.equal(s.batPct, 99)
assert.equal(s.batStatus, "Charging")
assert.ok(Math.abs(s.batPower - 8.627) < 0.001)  // microwatts -> W

// Missing hardware reports nothing rather than a misleading zero.
const empty = M.parseSensors("")
assert.equal(empty.cpuTemp, -1)
assert.equal(empty.gpuTemp, -1)
assert.equal(empty.gpuRuntime, "")
assert.equal(M.fmtTemp(-1), "—")
assert.equal(M.fmtRpm(0), "off")

// A suspended dGPU reports its runtime state without nvidia-smi telemetry.
const sleeping = M.parseSensors("gpu_runtime=suspended\n")
assert.equal(sleeping.gpuRuntime, "suspended")
assert.equal(sleeping.gpuTemp, -1)
assert.equal(sleeping.gpuPower, -1)

// ---------------------------------------------------------------- display
const MONITORS = JSON.stringify([
    { name: "HDMI-A-1", focused: true, width: 1920, height: 1080, refreshRate: 74.973, x: 0, y: 0, scale: 1.25,
      availableModes: ["1920x1080@74.97Hz", "1920x1080@60.00Hz", "1280x720@60.00Hz"] },
    { name: "eDP-1", focused: false, width: 1920, height: 1080, refreshRate: 60.004, x: -1536, y: 0, scale: 1.25,
      availableModes: ["1920x1080@60.00Hz", "1920x1080@144.00Hz"] }
])
const mon = M.parseMonitors(MONITORS)
// The built-in panel wins even when an external monitor has focus.
assert.equal(mon.name, "eDP-1")
assert.deepEqual(mon.rates, [60, 144])
assert.equal(mon.rate, 60)
// Must be the Lua eval form: `hyprctl keyword monitor` is rejected by
// Hyprland's non-legacy (Lua) config parser. Position and scale are repeated
// because hl.monitor replaces the whole rule.
assert.deepEqual(M.monitorCommand(mon, 144), ["hyprctl", "eval",
    'hl.monitor({ output = "eDP-1", mode = "1920x1080@144", position = "-1536x0", scale = 1.25 })'])
assert.equal(M.parseMonitors("not json"), null)
assert.equal(M.parseMonitors("[]"), null)

// ------------------------------------------------------------ hyprmoncfg
// Where the daemon runs, a refresh change must also be saved into its active
// profile or it reverts; where it does not, the runtime change stands alone.
const MONCFG_RUNNING = JSON.stringify({
    schema_version: 1, version: "1.15.0",
    daemon: { running: true },
    active_profile: { name: "MonLeft" }
})
assert.deepEqual(M.parseHyprmoncfgStatus(MONCFG_RUNNING), { managed: true, profile: "MonLeft" })
assert.deepEqual(M.parseHyprmoncfgStatus(JSON.stringify({ daemon: { running: false }, active_profile: { name: "MonLeft" } })),
    { managed: false, profile: "MonLeft" })
// A running daemon with no active profile has nothing to save into — saving
// would be `hyprmoncfg save ""`, so this must not count as managed.
assert.deepEqual(M.parseHyprmoncfgStatus(JSON.stringify({ daemon: { running: true } })),
    { managed: false, profile: "" })
// Binary missing entirely: the status call produces nothing parseable.
assert.deepEqual(M.parseHyprmoncfgStatus(""), { managed: false, profile: "" })
assert.deepEqual(M.parseHyprmoncfgStatus("command not found"), { managed: false, profile: "" })

// ---------------------------------------------------------------- gpu mode
assert.equal(M.gpuModeId(0, 0), "standard")
assert.equal(M.gpuModeId(0, 1), "eco")
assert.equal(M.gpuModeId(1, 0), "ultimate")
assert.deepEqual(JSON.parse(JSON.stringify(M.parseGpuQueue("dgpu_disable i 1\ngpu_mux_mode i -1\n"))), { dgpu_disable: 1, gpu_mux_mode: -1 })
assert.deepEqual(JSON.parse(JSON.stringify(M.parseGpuQueue("dgpu_disable \ngpu_mux_mode \n"))), { dgpu_disable: -1, gpu_mux_mode: -1 })

// ---------------------------------------------------------------- features
// asusctl 6.x names the charge limit ChargeControlEndThreshold; matching only
// on the word "battery" hid the limit slider on models that support it.
const INFO = `Supported Platform Properties:
[
    ChargeControlEndThreshold,
    ThrottlePolicy,
]
Supported Aura Modes:
[
    Static,
    Breathe,
]
Supported Aura Power Zones:
[
    Keyboard,
]
`
const f = M.parseSupportedFeatures(INFO)
assert.equal(f.hasBattery, true)
assert.deepEqual(f.auraModes, ["Static", "Breathe"])
assert.deepEqual(f.auraPowerZones, ["Keyboard"])
assert.equal(M.supportedEffects(f.auraModes).length, 2)

// Older models report no aura power zones and fall back to power-tuf.
const OLD_INFO = `Supported Aura Modes:
[
    Static,
]
`
assert.deepEqual(M.parseSupportedFeatures(OLD_INFO).auraPowerZones, [])

// ---------------------------------------------------------------- aura power
// Boolean switches: enabled states are present, disabled ones omitted, so a
// state has to be resent in full or asusctl reads the gaps as false.
assert.deepEqual(M.buildAuraPowerCommand("keyboard", { awake: true, boot: true, sleep: true, shutdown: false }),
    ["asusctl", "aura", "power", "keyboard", "--awake", "--boot", "--sleep"])
assert.deepEqual(M.buildAuraPowerCommand("lightbar", { awake: true, boot: false, sleep: false, shutdown: true }),
    ["asusctl", "aura", "power", "lightbar", "--awake", "--shutdown"])
assert.deepEqual(M.buildAuraPowerCommand("logo", {}), ["asusctl", "aura", "power", "logo"])
assert.deepEqual(M.auraPowerStates, ["awake", "boot", "sleep", "shutdown"])
assert.equal(M.auraZoneLabel("rear-glow"), "Rear glow")
assert.equal(M.auraZoneLabel("keyboard"), "Keyboard")

// ---------------------------------------------------------------- fan curves
const pts = M.parseFanPoints("30c:1%,49c:2%,60c:40%")
assert.deepEqual(pts, [{ temp: 30, speed: 1 }, { temp: 49, speed: 2 }, { temp: 60, speed: 40 }])
assert.equal(M.serializeFanPoints(pts), "30c:1%,49c:2%,60c:40%")
// Dragging past a neighbour reorders instead of crossing, and stays in bounds.
const moved = M.moveFanPoint(pts, 0, 200, -5)
assert.deepEqual(moved[moved.length - 1], { temp: 100, speed: 0 })

// ---------------------------------------------------------------- cpu boost
// Intel and AMD invert each other: no_turbo 0 = boost on, cpufreq/boost 1 = on.
assert.deepEqual(M.parseTurbo("kind=intel\nraw=0"), { kind: "intel", enabled: true, available: true })
assert.deepEqual(M.parseTurbo("kind=intel\nraw=1"), { kind: "intel", enabled: false, available: true })
assert.deepEqual(M.parseTurbo("kind=amd\nraw=1"), { kind: "amd", enabled: true, available: true })
assert.deepEqual(M.parseTurbo("kind=amd\nraw=0"), { kind: "amd", enabled: false, available: true })
assert.deepEqual(M.parseTurbo("kind=none"), { kind: "none", enabled: false, available: false })
assert.deepEqual(M.parseTurbo(""), { kind: "none", enabled: false, available: false })
// An unreadable file gives an empty value, which must not read as "on".
assert.equal(M.parseTurbo("kind=intel\nraw=").enabled, false)
assert.equal(M.turboPath("intel"), "/sys/devices/system/cpu/intel_pstate/no_turbo")
assert.equal(M.turboPath("amd"), "/sys/devices/system/cpu/cpufreq/boost")
// The value is inverted per vendor, and the write goes through pkexec tee so a
// polkit rule has one exact program to match.
const turboCmd = ["sh", "-c", 'printf %s "$1" | pkexec tee "$2" > /dev/null', "sh"]
assert.deepEqual(M.turboSetCommand("intel", true), turboCmd.concat(["0", M.turboPath("intel")]))
assert.deepEqual(M.turboSetCommand("intel", false), turboCmd.concat(["1", M.turboPath("intel")]))
assert.deepEqual(M.turboSetCommand("amd", true), turboCmd.concat(["1", M.turboPath("amd")]))
assert.deepEqual(M.turboSetCommand("amd", false), turboCmd.concat(["0", M.turboPath("amd")]))

// ---------------------------------------------------------------- services
// `is-active` alone cannot tell "installed but stopped" from "not installed",
// so the probe reports LoadState alongside it and presence is read from that.
const SERVICES = `asusd.service load=loaded active=active
supergfxd.service load=loaded active=inactive
nvidia-powerd.service load=not-found active=inactive
`
const svc = M.parseServiceStatus(SERVICES)
assert.deepEqual(svc.asusd, { load: "loaded", active: "active" })
assert.deepEqual(svc.supergfxd, { load: "loaded", active: "inactive" })
assert.deepEqual(svc.nvidiaPowerd, { load: "not-found", active: "inactive" })
assert.equal(M.servicePresent(svc.asusd), true)
assert.equal(M.serviceActive(svc.asusd), true)
assert.equal(M.serviceActive(svc.supergfxd), false)
assert.equal(M.servicePresent(svc.nvidiaPowerd), false)
assert.equal(M.serviceStateLabel(svc.asusd), "running")
assert.equal(M.serviceStateLabel(svc.supergfxd), "stopped")
assert.equal(M.serviceStateLabel(svc.nvidiaPowerd), "not installed")
assert.equal(M.serviceStateLabel(M.parseServiceStatus("asusd.service load=loaded active=failed").asusd), "failed")
// A read that has not happened yet must not look like "not installed", or the
// section would flash "not installed" before the first result lands.
assert.equal(M.servicePresent(undefined), false)
assert.deepEqual(M.parseServiceStatus("").asusd, { load: "", active: "" })
assert.equal(M.servicePresent(M.parseServiceStatus("").asusd), false)
// The unit list is what both the probe and the panel iterate.
assert.deepEqual(M.serviceUnits.map(function(s) { return s.unit }),
    ["asusd.service", "supergfxd.service", "nvidia-powerd.service"])
assert.ok(M.serviceStatusCommand()[2].indexOf("systemctl show -p LoadState --value") >= 0)
// The panel renders the first two as read-only chips and nvidia-powerd as a
// switch, so the slice has to keep those two first.
assert.deepEqual(M.serviceUnits.slice(0, 2).map(function(s) { return s.id }), ["asusd", "supergfxd"])

// ---------------------------------------------------------------- install offers
// An install is only offered for a unit that is genuinely absent: "not read yet"
// and "installed but stopped" both have to stay quiet, or the button would appear
// before the first probe answers.
assert.equal(M.serviceMissing(undefined), false)
assert.equal(M.serviceMissing(M.parseServiceStatus("").asusd), false)
assert.equal(M.serviceMissing(svc.supergfxd), false)
assert.equal(M.serviceMissing(svc.nvidiaPowerd), true)
assert.equal(M.serviceInstallable(M.serviceUnits[0], svc.asusd), false)
assert.equal(M.serviceInstallable(M.serviceUnits[2], svc.nvidiaPowerd), true)
assert.equal(M.serviceInstallable(null, svc.nvidiaPowerd), false)
assert.equal(M.serviceInstallable(M.serviceUnits[0], undefined), false)

// asusctl is what Omarchy's own installer adds for ROG hardware, so it goes
// through the repo adder; supergfxctl is AUR-only there. Each install enables its
// unit and holds the terminal open with Omarchy's done prompt.
assert.equal(M.serviceInstallPkgCommand("asusd"), "omarchy-pkg-add asusctl")
assert.equal(M.serviceInstallPkgCommand("supergfxd"), "omarchy-pkg-aur-add supergfxctl")
assert.equal(M.serviceInstallPkgCommand("nvidiaPowerd"), "omarchy-pkg-add nvidia-utils")
assert.equal(M.serviceInstallPkgCommand("nope"), "")
assert.deepEqual(M.serviceInstallCommand("asusd"), ["omarchy-launch-tui", "bash", "-c",
    "omarchy-pkg-add asusctl && sudo systemctl enable --now asusd.service; omarchy-show-done $?"])
assert.deepEqual(M.serviceInstallCommand("supergfxd"), ["omarchy-launch-tui", "bash", "-c",
    "omarchy-pkg-aur-add supergfxctl && sudo systemctl enable --now supergfxd.service; omarchy-show-done $?"])
assert.equal(M.serviceInstallCommand("nope"), null)
assert.equal(M.serviceInstallLabel("supergfxd"), "Install supergfxctl")
assert.equal(M.serviceInstallLabel("nope"), "Install", "no package name to spell out")
// The panel reads this flag to keep the NVIDIA offer off a laptop without NVIDIA
// hardware, since that package is the driver itself.
assert.equal(M.serviceUnits[2].nvidia, true)
assert.equal(M.serviceUnit("asusd").source, "repo")
assert.equal(M.serviceUnit("supergfxd").source, "aur")
assert.equal(M.serviceUnit("nvidiaPowerd").unit, "nvidia-powerd.service")
assert.equal(M.serviceUnit("nope"), null)
assert.ok(M.serviceInstallScript("asusd").indexOf("sudo systemctl enable --now asusd.service") >= 0)
assert.equal(M.serviceInstallScript("nope"), "")
assert.equal(M.serviceInstallScript("asusd").indexOf("omarchy-launch-tui"), -1, "the launcher belongs to the command, not the script")

// ---------------------------------------------------------------- lid/hibernate
assert.deepEqual(M.lidActions.slice(0, 3), ["auto", "suspend", "suspend-then-hibernate"])
// The global control has no "auto" (Suspend is systemd's default).
assert.deepEqual(M.lidActionsGlobal, ["suspend", "suspend-then-hibernate", "hibernate", "lock", "ignore", "poweroff"])
assert.equal(M.lidActionLabel("ignore"), "Do nothing")
assert.equal(M.lidActionLabel("bogus"), "Auto")
assert.equal(M.hibernateDelayLabel("60min"), "1h")
const lidCmd = M.lidApplyCommand("suspend-then-hibernate", "60min")
assert.deepEqual(lidCmd.slice(0, 2), ["pkexec", "sh"])
assert.ok(lidCmd[3].indexOf("HandleLidSwitch=%s") >= 0)
assert.ok(lidCmd[3].indexOf("suspend-then-hibernate") >= 0)
assert.ok(lidCmd[3].indexOf("HibernateDelaySec=%s") >= 0)
assert.ok(lidCmd[3].indexOf("60min") >= 0)
assert.ok(lidCmd[3].indexOf("systemctl kill -s HUP systemd-logind") >= 0)
// The right-most hibernate slider position is "Never" -> HibernateDelaySec=infinity.
assert.ok(M.lidApplyCommand("suspend-then-hibernate", "infinity")[3].indexOf("HibernateDelaySec=%s") >= 0)
assert.ok(M.lidApplyCommand("suspend-then-hibernate", "infinity")[3].indexOf("infinity") >= 0)
// "auto" removes the drop-ins rather than writing them.
const lidAuto = M.lidApplyCommand("auto", "auto")
assert.ok(lidAuto[3].indexOf("rm -f /etc/systemd/logind.conf.d/50-asus-lid.conf") >= 0)
assert.ok(lidAuto[3].indexOf("rm -f /etc/systemd/sleep.conf.d/50-asus-hibernate.conf") >= 0)
assert.equal(lidAuto[3].indexOf("HandleLidSwitch"), -1)

console.log("ok - all Model.js checks passed")
