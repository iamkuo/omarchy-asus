import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "io.github.moneytosms.asus"
    ipcTarget: "io.github.moneytosms.asus"
    manageIpc: false

    // Hosts like the Plugin Drawer set this to their own bar button so a
    // hidden/collapsed widget's panel still opens under the right icon
    // instead of the (invisible, off-bar) button this plugin owns itself.
    property var anchorItem: null

    // Reusable draggable fan-curve editor. Shows a temp/speed line with
    // draggable points; commits the whole curve via onCommit(points) on
    // release, and offers a per-fan reset via onReset(). Points never leave
    // [30,100]c / [0,100]% and stay ordered by temp — see Model.moveFanPoint.
    component FanCurveEditor: Column {
        id: editor
        property var points: []
        property bool enabledState: false
        property color accent: "#44cc44"
        property color foreground: "white"
        property string fontFamily: "monospace"
        property bool interactive: true
        signal commit(var points)
        signal reset()

        width: parent ? parent.width : 0
        spacing: Style.space(4)

        Rectangle {
            width: parent.width
            height: Style.space(64)
            radius: Style.cornerRadius
            color: Qt.rgba(editor.foreground.r, editor.foreground.g, editor.foreground.b, 0.04)
            opacity: editor.interactive ? 1 : 0.4

            Canvas {
                id: canvas
                anchors.fill: parent
                anchors.margins: Style.space(6)
                renderStrategy: Canvas.Immediate

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    if (editor.points.length < 2) return
                    var w = width, h = height
                    ctx.strokeStyle = Qt.rgba(editor.foreground.r, editor.foreground.g, editor.foreground.b, 0.6)
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    for (var i = 0; i < editor.points.length; i++) {
                        var px = (editor.points[i].temp - 30) / 70 * w
                        var py = h - (editor.points[i].speed / 100) * h
                        if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
                    }
                    ctx.stroke()
                }

                Connections { target: editor; function onPointsChanged() { canvas.requestPaint() } }

                Repeater {
                    model: editor.points
                    Rectangle {
                        id: handle
                        required property var modelData
                        required property int index
                        width: Style.space(10); height: Style.space(10); radius: Style.space(5)
                        color: editor.enabledState ? editor.accent : Qt.rgba(editor.foreground.r, editor.foreground.g, editor.foreground.b, 0.4)
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.3)
                        x: (modelData.temp - 30) / 70 * canvas.width - width / 2
                        y: canvas.height - (modelData.speed / 100) * canvas.height - height / 2

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Style.space(4)
                            enabled: editor.interactive
                            cursorShape: Qt.PointingHandCursor
                            drag.target: handle
                            drag.axis: Drag.XAndYAxis
                            drag.minimumX: -handle.width / 2
                            drag.maximumX: canvas.width - handle.width / 2
                            drag.minimumY: -handle.height / 2
                            drag.maximumY: canvas.height - handle.height / 2
                            onPositionChanged: {
                                if (!drag.active) return
                                var temp = (handle.x + handle.width / 2) / canvas.width * 70 + 30
                                var speed = (1 - (handle.y + handle.height / 2) / canvas.height) * 100
                                editor.points = Model.moveFanPoint(editor.points, index, temp, speed)
                            }
                            onReleased: editor.commit(editor.points)
                        }
                    }
                }
            }

            // Sits under the handles so it never eats a drag, and explains the
            // axes — the graph has no room for labelled ones.
            MouseArea {
                id: curveHelp
                anchors.fill: parent
                z: -1
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
            PanelToolTip {
                visible: curveHelp.containsMouse
                text: "Fan curve: temperature (30–100 °C) left to right,\nfan speed (0–100%) bottom to top.\nDrag a point to change it."
            }

            Text {
                anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: Style.space(2)
                text: editor.points.length + " pts"
                color: Qt.darker(editor.foreground, 1.6)
                font.family: editor.fontFamily
                font.pixelSize: 8
            }
        }

        Row {
            width: parent.width
            Item { width: parent.width - resetBtn.width; height: 1 }
            Button {
                id: resetBtn
                text: "Reset"
                tooltipText: "Restore this profile's default fan curves."
                fontSize: Style.font.caption
                foreground: editor.foreground
                fontFamily: editor.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                onClicked: editor.reset()
            }
        }
    }

    // Compact readout tile used by the sensor strip: a caption, a big value,
    // and an optional second line. Kept dumb so the strip can reflow it into
    // however many columns the panel width allows.
    component SensorTile: Rectangle {
        id: tile
        property string caption: ""
        property string value: ""
        property string sub: ""
        property color valueColor: "white"
        property color foreground: "white"
        property string fontFamily: "monospace"
        property string tip: ""

        height: Style.space(46)
        radius: Style.cornerRadius
        color: Qt.rgba(tile.foreground.r, tile.foreground.g, tile.foreground.b, 0.05)

        MouseArea { id: tileHelp; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
        PanelToolTip { visible: tile.tip !== "" && tileHelp.containsMouse; text: tile.tip }

        Column {
            anchors.centerIn: parent
            spacing: Style.space(1)
            Text {
                text: tile.caption
                color: Qt.darker(tile.foreground, 1.7)
                font.family: tile.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: tile.value
                color: tile.valueColor
                font.family: tile.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                visible: tile.sub !== ""
                text: tile.sub
                color: Qt.darker(tile.foreground, 1.5)
                font.family: tile.fontFamily; font.pixelSize: Style.font.caption
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    property string currentProfile: ""
    property bool profileLoaded: false
    property bool infoLoaded: false
    property var profiles: ["Quiet", "Balanced", "Performance"]
    property int profileIndex: 1
    property var acProfile: ({ ac: "", battery: "" })
    property var supported: ({ hasAura: false, hasFanCurve: false, hasBattery: false, hasProfile: false, auraModes: [] })
    property bool fanCurveEnabled: false
    property int batteryLimit: 100
    // "Charge to <target>% once" plan: the limit is temporarily set to target
    // and restored to `restore` (the limit in effect at the time) once the
    // battery reaches it. Persisted so a shell restart does not lose it.
    property var oneshotPlan: null
    property int oneshotTarget: 100
    readonly property bool oneshotActive: root.oneshotPlan !== null
    readonly property string oneshotStateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy-asus-oneshot.json"
    property bool asusctlAvailable: false
    property bool cursorActive: false

    // CPU boost switch — sysfs, not asusctl, so it is read on the panel's own
    // tick like everything else. `kind` is "intel", "amd" or "none"; "none"
    // hides the control, since a machine with neither file has no switch.
    property var turbo: ({ kind: "none", enabled: false, available: false })
    // Distinguishes "not probed yet" from "probed, no switch here" — without it a
    // mode switch on a laptop with no boost file would re-probe forever.
    property bool turboLoaded: false
    // A mode switch can happen from the bar with the panel closed, before the
    // first probe has landed. The mode is parked here and applied when it does.
    property string pendingBoostMode: ""
    // Services the panel's controls depend on: asusd, supergfxd, nvidia-powerd.
    // One systemctl round trip fills all three (see serviceStatusCommand).
    property var services: ({})
    // Last failed write. Actions are applied optimistically and reverted when the
    // command fails, which is the one outcome re-reading state cannot explain.
    property string actionError: ""
    readonly property var nvidiaPowerd: root.services.nvidiaPowerd || ({ load: "", active: "" })
    readonly property bool nvidiaPowerdPresent: Model.servicePresent(root.nvidiaPowerd)
    // nvidia-powerd ships with the driver package, so offering to install it only
    // makes sense where the firmware reports the NVIDIA attributes this panel
    // already reads. On an AMD-only laptop the offer would be noise, and acting
    // on it would pull a driver nobody asked for.
    readonly property bool nvidiaDgpu: !!(root.armourySupported.nvTempTarget || root.armourySupported.nvDynBoost)

    // Live sensors — refreshed on a faster tick than the asusctl state, since
    // temps and fan speeds are the numbers you actually watch move.
    property var sensors: ({ cpuTemp: -1, gpuTemp: -1, gpuPower: -1, gpuUtil: -1, gpuRuntime: "", fanCpu: -1, fanGpu: -1, batPct: -1, batStatus: "", batPower: -1 })
    readonly property bool hasNvidia: sensors.gpuRuntime !== ""
    readonly property bool nvidiaSleeping: sensors.gpuRuntime === "suspended"

    // Display — the built-in panel's current/available refresh rates, read
    // from Hyprland rather than asusctl (which has no display controls).
    property var monitor: null

    // Whether hyprmoncfg is installed, and whether its daemon is actively
    // managing displays. When it is, a runtime mode change has to be saved
    // back into the active profile or the daemon reverts it seconds later.
    property bool hyprmoncfgAvailable: false
    property bool hyprmoncfgManaged: false
    property string hyprmoncfgProfile: ""

    // ---- Tabs -----------------------------------------------------------
    property string tabKey: "main"
    readonly property var tabs: {
        var t = [{ key: "main", label: "Main" }]
        if (root.supported.hasAura || !root.infoLoaded) t.push({ key: "rgb", label: "RGB" })
        if (root.supported.hasFanCurve || !root.infoLoaded) t.push({ key: "fan", label: "Fan" })
        t.push({ key: "advanced", label: "Advanced" })
        return t
    }
    readonly property int tabIndex: { for (var i = 0; i < tabs.length; i++) if (tabs[i].key === tabKey) return i; return 0 }
    function selectTab(index) {
        if (tabs.length === 0) return
        var n = tabs.length, i = ((index % n) + n) % n
        tabKey = tabs[i].key
    }

    // RGB
    property string currentEffect: "static"
    property int colorR: 255
    property int colorG: 0
    property int colorB: 0
    property int color2R: 0
    property int color2G: 0
    property int color2B: 255
    property string currentSpeed: "med"
    property string currentDirection: "left"
    property bool ledAwake: true
    property bool ledBoot: true
    property bool ledSleep: true
    property string ledBrightness: "med"
    // Per-zone aura power (the 2021+ `asusctl aura power <zone>` API). Only the
    // zones the laptop reports are shown. asusctl does not report the states
    // back, so the panel tracks what it last set, like the legacy toggles.
    property var auraPowerZones: []
    property var auraPowerState: ({})
    readonly property string colorHex: Model.rgbToHex(colorR, colorG, colorB)
    readonly property string color2Hex: Model.rgbToHex(color2R, color2G, color2B)
    readonly property color liveColor: Qt.rgba(colorR / 255, colorG / 255, colorB / 255, 1)
    readonly property color liveColor2: Qt.rgba(color2R / 255, color2G / 255, color2B / 255, 1)

    readonly property var auraSupportedEffects: Model.supportedEffects(root.supported.auraModes)
    readonly property var effectDef: { for (var i = 0; i < Model.effects.length; i++) { if (Model.effects[i].id === currentEffect) return Model.effects[i] }; return Model.effects[0] }
    readonly property bool needsColor: effectDef.params.indexOf("color") >= 0
    readonly property bool needsColor2: effectDef.params.indexOf("color2") >= 0
    readonly property bool needsSpeed: effectDef.params.indexOf("speed") >= 0
    readonly property bool needsDirection: effectDef.params.indexOf("direction") >= 0

    // Fan curves
    property bool cpuFanEnabled: false
    property bool gpuFanEnabled: false
    property bool midFanEnabled: false
    property bool hasMidFan: false
    property var cpuFanPoints: []
    property var gpuFanPoints: []
    property var midFanPoints: []
    // Which profile's curves the Fan tab is editing. asusctl stores one curve
    // set per power profile, so — like G-Helper — the editor targets a chosen
    // profile rather than silently always writing the active one.
    property string fanEditProfile: ""
    readonly property string fanProfile: fanEditProfile || currentProfile || "Balanced"
    // Power-plan editor target (Advanced tab): the mode whose per-mode settings
    // (screen refresh and CPU boost) are shown and edited together.
    property string planKey: ""
    readonly property string plan: root.planKey || root.currentProfile || "Balanced"

    // Armoury — armourySupported gates each Advanced control per-model, since
    // `asusctl armoury list` only reports attributes the running laptop
    // actually exposes (no dGPU / no panel overdrive on some models).
    property var armourySupported: ({ panelOverdrive: false, gpuMux: false, dgpuDisable: false, pptPl1: false, pptPl2: false, pptPl3: false, nvDynBoost: false, nvTempTarget: false })
    property var armouryDefaults: ({})
    property bool panelOverdrive: false
    property bool gpuMux: false // true = MUX on dGPU (Ultimate)
    property bool dgpuDisable: false
    // asusd (6.4+) queues GPU writes until reboot instead of applying them,
    // so `armoury list` keeps reporting the old value. -1 = nothing queued.
    property int queuedMux: -1
    property int queuedDgpu: -1
    // Eco picked while running Ultimate. The kernel refuses dgpu_disable while
    // the MUX is on the dGPU, so only the MUX is queued now; the marker file
    // survives the reboot and the dGPU-off write is queued on the next boot.
    property bool ecoPending: false
    readonly property string ecoMarker: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy-asus-eco-pending"
    property int pptPl1: 115
    property int pptPl1Min: 25
    property int pptPl1Max: 45
    property int pptPl2: 135
    property int pptPl2Min: 35
    property int pptPl2Max: 60
    property int pptPl3: 65
    property int pptPl3Min: 35
    property int pptPl3Max: 80
    property int nvDynBoost: 25
    property int nvDynBoostMin: 0
    property int nvDynBoostMax: 25
    property int nvTempTarget: 87
    property int nvTempTargetMin: 75
    property int nvTempTargetMax: 87

    // GPU mode is derived from the mux/dgpu pair rather than stored, so it
    // can never drift out of sync with what the firmware actually reports.
    // gpuMode is what the next boot will use (queued value wins);
    // activeGpuMode is what is running now.
    readonly property bool targetMux: queuedMux >= 0 ? queuedMux === 0 : gpuMux
    readonly property bool targetDgpu: queuedDgpu >= 0 ? queuedDgpu === 1 : dgpuDisable
    readonly property string gpuMode: ecoPending ? "eco" : Model.gpuModeId(targetMux, targetDgpu)
    readonly property string activeGpuMode: Model.gpuModeId(gpuMux, dgpuDisable)
    readonly property bool gpuRebootPending: gpuMode !== activeGpuMode
    readonly property bool hasGpuMode: armourySupported.gpuMux || armourySupported.dgpuDisable

    readonly property bool showBatteryLimit: setting("showBatteryLimit", true) === true
    readonly property int refreshInterval: Math.max(5, Math.min(60, Number(setting("refreshIntervalSec", 10)) || 10)) * 1000
    // Optional plugin-side default profile per power source, applied when the
    // charger is plugged or unplugged. "Auto" leaves the choice to the profile
    // asusd already has saved for that source.
    readonly property string defaultProfileAc: String(setting("defaultProfileAc", "Auto"))
    readonly property string defaultProfileBattery: String(setting("defaultProfileBattery", "Auto"))
    // Last lid/hibernate values actually written, so a plan switch that resolves
    // to the same values does not re-run the root write. Empty = not applied yet.
    property string appliedLid: ""
    property string appliedHib: ""

    function refresh() {
        if (!asusctlAvailable) { checkAsusctl.running = true; return }
        if (!profileProc.running) profileProc.running = true
        if (!infoProc.running) infoProc.running = true
        if (supported.hasBattery && !batteryProc.running) batteryProc.running = true
        if (!ledProc.running) ledProc.running = true
        if (!armouryProc.running) armouryProc.running = true
        if (!monitorProc.running) monitorProc.running = true
        if (hyprmoncfgAvailable && !hyprmoncfgProc.running) hyprmoncfgProc.running = true
        if (supported.hasFanCurve) { if (!fanDetailProc.running) fanDetailProc.running = true }
        if (!turboProc.running) turboProc.running = true
        if (!serviceProc.running) serviceProc.running = true
    }

    // Switching mode also applies that mode's own refresh rate and boost plan.
    function setProfile(p) {
        if (!p || actionProc.running) return
        // Mode plus any per-plan firmware limits in one call, so the limits land
        // right after the profile that owns them.
        actionProc.command = ["sh", "-c", Model.profileCommand(p, UPower.onBattery).join(" ") + root.planLimitsCommand(p)]
        actionProc.running = true
        applyProfileRefresh(p)
        applyProfileBoost(p)
        applyLid(p)
    }
    function cycleProfile(d) { profileIndex = Model.selectProfileIndex(profileIndex, d, profiles); setProfile(profiles[profileIndex]) }

    // CPU boost. asusctl has no equivalent and the sysfs flag is root-owned, so
    // the switch is applied optimistically and put back if pkexec was cancelled
    // (exit 126/127) or the write failed — see turboWriteProc.
    function setTurbo(on) {
        if (!root.turbo.available || turboWriteProc.running || on === root.turbo.enabled) return
        turboWriteProc.prevEnabled = root.turbo.enabled
        root.turbo = { kind: root.turbo.kind, enabled: on, available: true }
        turboWriteProc.command = Model.turboSetCommand(root.turbo.kind, on)
        turboWriteProc.running = true
    }
    function toggleTurbo() { setTurbo(!root.turbo.enabled) }

    // A missing unit is the one state a button can fix outright. The install runs
    // in Omarchy's own terminal so pacman can prompt for sudo and show what it
    // does, which means this Process only reports whether the terminal opened —
    // the result of the install itself shows up on the next refresh.
    function installService(id) {
        var cmd = Model.serviceInstallCommand(id)
        if (!cmd || installProc.running) return
        installProc.pkgCommand = Model.serviceInstallPkgCommand(id)
        installProc.command = cmd
        installProc.running = true
    }

    // Failed writes get a line of their own, cleared after a few seconds.
    function showActionError(msg) { root.actionError = msg; errorClearTimer.restart() }

    function applyEffect() {
        if (!supported.hasAura) return
        var params = {}
        if (needsColor) params.color = colorHex
        if (needsColor2) params.color2 = color2Hex
        if (needsSpeed) params.speed = currentSpeed
        if (needsDirection) params.direction = currentDirection
        actionProc.command = Model.buildAuraCommand(currentEffect, params); actionProc.running = true
    }
    function selectEffect(id) { currentEffect = id; applyEffect() }
    function setPresetColor(hex) { var r = Model.hexToRgb(hex); colorR = r.r; colorG = r.g; colorB = r.b; applyEffect() }
    function setPresetColor2(hex) { var r = Model.hexToRgb(hex); color2R = r.r; color2G = r.g; color2B = r.b; applyEffect() }

    // power-tuf takes all three states in one call, so each toggle resends the
    // full triple — sending only the changed flag makes asusctl default the
    // omitted ones back to false.
    function applyLedPower() {
        actionProc.command = ["asusctl", "aura", "power-tuf",
                              "--awake", ledAwake ? "true" : "false", "--keyboard",
                              "--boot", ledBoot ? "true" : "false",
                              "--sleep", ledSleep ? "true" : "false"]
        actionProc.running = true
    }
    function setLedPower(on) { ledAwake = on; applyLedPower() }
    function setLedBoot(on) { ledBoot = on; applyLedPower() }
    function setLedSleep(on) { ledSleep = on; applyLedPower() }
    function setLedBrightness(level) { ledBrightness = level; actionProc.command = ["asusctl", "leds", "set", level]; actionProc.running = true }
    function setBatteryLimit(l) { if (!supported.hasBattery) return; var c = Math.max(20, Math.min(100, Math.round(l))); actionProc.command = ["asusctl", "battery", "limit", String(c)]; actionProc.running = true }
    // Charge to a target once: set the limit to it, remember the limit to
    // restore, and let the sensor tick restore it when the battery arrives.
    function startOneshot(target) {
        if (!supported.hasBattery) return
        var t = Math.max(20, Math.min(100, Math.round(target)))
        root.oneshotPlan = { target: t, restore: Math.max(20, Math.min(100, Math.round(root.batteryLimit || t))) }
        persistOneshotState()
        setBatteryLimit(t)
    }
    // Cancel a running one-shot and put the saved limit straight back. Bail out
    // (keeping the plan) if asusctl support hasn't loaded yet — the sensor tick
    // can fire before `supported` is populated, and clearing the plan then would
    // silently drop the restore.
    function stopOneshot() {
        if (!root.oneshotPlan || !supported.hasBattery) return
        var r = root.oneshotPlan.restore
        root.oneshotPlan = null
        persistOneshotState()
        setBatteryLimit(r)
    }
    function persistOneshotState() {
        if (root.oneshotPlan)
            oneshotWriteProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", root.oneshotStateFile, Model.oneshotStateJson(root.oneshotPlan)]
        else
            oneshotWriteProc.command = ["rm", "-f", root.oneshotStateFile]
        oneshotWriteProc.running = true
    }

    // Per-zone aura power. Each zone's state is tracked locally (asusctl cannot
    // read it back) and the whole set is resent on every change, since the
    // omitted switches are what asusctl reads as "disabled".
    function auraPowerOn(zone, state) { var s = root.auraPowerState[zone]; return !!(s && s[state]) }
    function setAuraPower(zone, state, on) {
        var cur = root.auraPowerState[zone] || {}
        var next = { awake: !!cur.awake, boot: !!cur.boot, sleep: !!cur.sleep, shutdown: !!cur.shutdown }
        next[state] = on
        var all = {}
        for (var k in root.auraPowerState) all[k] = root.auraPowerState[k]
        all[zone] = next
        root.auraPowerState = all
        actionProc.command = Model.buildAuraPowerCommand(zone, next)
        actionProc.running = true
    }
    function initAuraPowerState(zones) {
        if (root.auraPowerZones.length > 0) { root.auraPowerZones = zones; return }
        var st = {}
        for (var i = 0; i < zones.length; i++) st[zones[i]] = { awake: true, boot: true, sleep: true, shutdown: false }
        root.auraPowerState = st
        root.auraPowerZones = zones
    }

    // The RGB header's on/off pill tracks the keyboard's "awake" power state.
    // On the newer zone API that lives in auraPowerState; on old models it is
    // the power-tuf flag, so both paths route through these helpers.
    readonly property bool hasKeyboardZone: root.auraPowerZones.indexOf("keyboard") >= 0
    readonly property bool keyboardLit: root.hasKeyboardZone ? root.auraPowerOn("keyboard", "awake") : root.ledAwake
    function toggleKeyboardPower() {
        if (root.hasKeyboardZone) root.setAuraPower("keyboard", "awake", !root.auraPowerOn("keyboard", "awake"))
        else root.setLedPower(!root.ledAwake)
    }

    // Plug/unplug only switches the power mode (its per-source default profile).
    // The screen refresh rate belongs to the mode itself — see
    // applyProfileRefresh — so this deliberately does not touch fps.
    function defaultProfileFor(source) { return source === "battery" ? root.defaultProfileBattery : root.defaultProfileAc }
    function applyDefaultProfile() {
        if (!asusctlAvailable) return
        var prof = UPower.onBattery ? root.defaultProfileBattery : root.defaultProfileAc
        if (prof && prof !== "Auto") setProfile(prof)
    }
    // Persist a per-source mode to shell.json through the bar settings API, so it
    // survives restarts and is the same value the settings UI edits. When the
    // edited source is active, apply it right away; otherwise it takes effect on
    // the next plug/unplug.
    function setDefaultProfile(source, value) {
        var key = source === "battery" ? "defaultProfileBattery" : "defaultProfileAc"
        persistProc.command = ["omarchy", "bar", "set", moduleName, key, value]
        persistProc.running = true
        if ((source === "battery") === UPower.onBattery && value !== "Auto") setProfile(value)
    }

    // Each performance mode carries its own default refresh rate, applied when
    // the mode is switched to. Stored as refreshQuiet/refreshBalanced/
    // refreshPerformance in shell.json.
    function profileKeyFor(name) {
        var n = String(name || "").toLowerCase()
        if (n.indexOf("quiet") >= 0 || n.indexOf("silent") >= 0) return "Quiet"
        if (n.indexOf("performance") >= 0 || n.indexOf("turbo") >= 0) return "Performance"
        return "Balanced"
    }
    function profileRefreshFor(name) { return String(setting("refresh" + root.profileKeyFor(name), "Auto")) }
    function applyProfileRefresh(name) {
        var hz = root.profileRefreshFor(name)
        if (hz === "Auto" || !root.monitor) return
        setRefreshRate(Number(hz))
    }
    function setProfileRefresh(name, value) {
        persistProc.command = ["omarchy", "bar", "set", moduleName, "refresh" + root.profileKeyFor(name), String(value)]
        persistProc.running = true
        if (name === root.currentProfile && String(value) !== "Auto" && root.monitor) setRefreshRate(Number(value))
    }

    // Each performance mode also carries its own CPU boost setting, the way
    // G-Helper stores it per mode, applied when the mode is switched to. Stored
    // as boostQuiet/boostBalanced/boostPerformance in shell.json. "Auto" leaves
    // whatever is set now alone, so a mode that does not care about boost never
    // fights the toggle above.
    function profileBoostFor(name) { return String(setting("boost" + root.profileKeyFor(name), "Auto")) }
    function applyProfileBoost(name) {
        var want = root.profileBoostFor(name)
        if (want === "Auto") { root.pendingBoostMode = ""; return }
        // The switch has to be read before it can be written (kind decides the
        // path and the polarity). If the probe has not landed yet — a mode
        // switch from the bar with the panel closed — park the mode and apply it
        // when it does; on a laptop with no boost file the parked mode is
        // dropped instead of re-probing forever.
        if (!root.turboLoaded) {
            root.pendingBoostMode = name
            if (!turboProc.running) turboProc.running = true
            return
        }
        if (!root.turbo.available) return
        setTurbo(want === "On")
    }
    function setProfileBoost(name, value) {
        persistProc.command = ["omarchy", "bar", "set", moduleName, "boost" + root.profileKeyFor(name), String(value)]
        persistProc.running = true
        // Editing the plan for the mode in use applies it straight away; the
        // others take effect when you switch to them.
        if (name === root.currentProfile) applyProfileBoost(name)
    }

    // Per-plan firmware limits (PL1/PL2/PL3, GPU boost/temp), stored as
    // <key><Plan> in shell.json. "Auto" leaves the limit unchanged when the plan
    // is switched to, matching the refresh/boost plans.
    function planLimitAttr(key) {
        return ({ pl1: "ppt_pl1_spl", pl2: "ppt_pl2_sppt", pl3: "ppt_pl3_fppt", nvBoost: "nv_dynamic_boost", nvTemp: "nv_temp_target" })[key] || ""
    }
    function planLimitValue(name, key) { return String(setting(key + root.profileKeyFor(name), "Auto")) }
    function setPlanLimit(name, key, value) {
        persistProc.command = ["omarchy", "bar", "set", moduleName, key + root.profileKeyFor(name), String(value)]
        persistProc.running = true
        if (name === root.currentProfile && String(value) !== "Auto") setArmouryAttr(root.planLimitAttr(key), Math.round(Number(value)))
    }
    function setPlanLimitAuto(name, key) {
        persistProc.command = ["omarchy", "bar", "set", moduleName, key + root.profileKeyFor(name), "Auto"]
        persistProc.running = true
    }
    // Auto is a toggle: clicking it off seeds an explicit value (the current
    // live one) so the slider has something to start from.
    function togglePlanLimitAuto(name, key, fallback) {
        if (root.planLimitValue(name, key) === "Auto") root.setPlanLimit(name, key, Math.round(Number(fallback)))
        else root.setPlanLimitAuto(name, key)
    }
    function planLimitsCommand(name) {
        var keys = ["pl1", "pl2", "pl3", "nvBoost", "nvTemp"]
        var s = ""
        for (var i = 0; i < keys.length; i++) {
            var v = root.planLimitValue(name, keys[i])
            if (v !== "Auto") s += " && asusctl armoury set " + root.planLimitAttr(keys[i]) + " " + Math.round(Number(v))
        }
        return s
    }
    // Split the same way the global limits above are, so the plan editor groups
    // CPU and GPU the same way.
    function planCpuLimitRows() {
        return [
            { key: "pl1", label: "PL1", unit: "W", supported: root.armourySupported.pptPl1, minimum: root.pptPl1Min, maximum: root.pptPl1Max, fallback: root.pptPl1 },
            { key: "pl2", label: "PL2", unit: "W", supported: root.armourySupported.pptPl2, minimum: root.pptPl2Min, maximum: root.pptPl2Max, fallback: root.pptPl2 },
            { key: "pl3", label: "PL3", unit: "W", supported: root.armourySupported.pptPl3, minimum: root.pptPl3Min, maximum: root.pptPl3Max, fallback: root.pptPl3 }
        ]
    }
    function planGpuLimitRows() {
        return [
            { key: "nvBoost", label: "Boost", unit: "W", supported: root.armourySupported.nvDynBoost, minimum: root.nvDynBoostMin, maximum: root.nvDynBoostMax, fallback: root.nvDynBoost },
            { key: "nvTemp", label: "Temp", unit: "°C", supported: root.armourySupported.nvTempTarget, minimum: root.nvTempTargetMin, maximum: root.nvTempTargetMax, fallback: root.nvTempTarget }
        ]
    }

    // Lid action + hibernate delay. The global value is the base; a plan can
    // override it (Auto = use the global). Applied as systemd drop-ins through
    // pkexec (see Model.lidApplyCommand), so it needs the polkit rule in the
    // README. Skipped when the resolved values are already in effect.
    function globalLidValue() { return String(setting("lidAction", "suspend")) }
    function globalHibValue() { return String(setting("hibernateDelay", "auto")) }
    function lidFor(name) { return String(setting("lid" + root.profileKeyFor(name), "auto")) }
    function hibFor(name) { return String(setting("hib" + root.profileKeyFor(name), "auto")) }
    function effectiveLid(name) { var v = root.lidFor(name); return v !== "auto" ? v : root.globalLidValue() }
    function effectiveHib(name) { var v = root.hibFor(name); return v !== "auto" ? v : root.globalHibValue() }
    function applyLidValues(lid, hib) {
        // Suspend with no delay is systemd's own default, so write no drop-in
        // for it (and remove any previous one).
        var writeLid = (lid === "suspend" && hib === "auto") ? "auto" : lid
        if (lid === root.appliedLid && hib === root.appliedHib) return
        root.appliedLid = lid
        root.appliedHib = hib
        lidProc.command = Model.lidApplyCommand(writeLid, hib)
        lidProc.running = true
    }
    function applyLid(name) { root.applyLidValues(root.effectiveLid(name), root.effectiveHib(name)) }
    function setLidAction(value) {
        persistProc.command = ["omarchy", "bar", "set", moduleName, "lidAction", String(value)]
        persistProc.running = true
        root.applyLidValues(String(value), root.effectiveHib(root.currentProfile))
    }
    function setHibDelay(value) {
        persistProc.command = ["omarchy", "bar", "set", moduleName, "hibernateDelay", String(value)]
        persistProc.running = true
        root.applyLidValues(root.effectiveLid(root.currentProfile), String(value))
    }
    function setPlanLid(name, value) {
        persistProc.command = ["omarchy", "bar", "set", moduleName, "lid" + root.profileKeyFor(name), String(value)]
        persistProc.running = true
        if (name === root.currentProfile)
            root.applyLidValues(String(value) !== "auto" ? String(value) : root.globalLidValue(), root.effectiveHib(name))
    }
    function setPlanHib(name, value) {
        persistProc.command = ["omarchy", "bar", "set", moduleName, "hib" + root.profileKeyFor(name), String(value)]
        persistProc.running = true
        if (name === root.currentProfile)
            root.applyLidValues(root.effectiveLid(name), String(value) !== "auto" ? String(value) : root.globalHibValue())
    }
    // Hibernate delay ("auto", e.g. "60min", or "infinity" = never hibernate) as
    // slider minutes + a label. The right-most slider position is "Never".
    function hibValueMinutes(state) { return state === "auto" ? 60 : (state === "infinity" ? 180 : (parseInt(state) || 60)) }
    function hibValueLabel(state) { return state === "auto" ? "Auto" : (state === "infinity" ? "Never" : (parseInt(state) || 60) + " min") }
    function hibValueFromSlider(v) { return Math.round(v) >= 180 ? "infinity" : Math.round(v) + "min" }

    // Fan curves — every write is gated on profileLoaded so an action never
    // silently lands on the wrong (hardcoded "Balanced") profile because the
    // real active profile hadn't loaded yet. This was the root cause of fan
    // controls appearing to "not work sometimes".
    function toggleFanCurves() { if (!supported.hasFanCurve || !profileLoaded) return; var n = !fanCurveEnabled; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--enable-fan-curves", n ? "true" : "false"]; actionProc.running = true }
    function toggleCpuFan() { if (!profileLoaded) return; var n = !cpuFanEnabled; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--enable-fan-curve", n ? "true" : "false", "--fan", "cpu"]; actionProc.running = true }
    function toggleGpuFan() { if (!profileLoaded) return; var n = !gpuFanEnabled; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--enable-fan-curve", n ? "true" : "false", "--fan", "gpu"]; actionProc.running = true }
    function toggleMidFan() { if (!profileLoaded || !hasMidFan) return; var n = !midFanEnabled; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--enable-fan-curve", n ? "true" : "false", "--fan", "mid"]; actionProc.running = true }
    function resetFanCurves() { if (!profileLoaded) return; actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--default"]; actionProc.running = true }
    function applyFanCurve(fan, points) {
        if (!profileLoaded || actionProc.running) return
        actionProc.command = ["asusctl", "fan-curve", "--mod-profile", fanProfile, "--fan", fan, "--data", Model.serializeFanPoints(points)]
        actionProc.running = true
    }
    function selectFanProfile(p) { if (!p || p === fanProfile) return; fanEditProfile = p; if (!fanModProc.running) fanModProc.running = true }

    function setArmouryAttr(a, v) { actionProc.command = ["asusctl", "armoury", "set", a, String(v)]; actionProc.running = true }
    function togglePanelOverdrive() { panelOverdrive = !panelOverdrive; setArmouryAttr("panel_overdrive", panelOverdrive ? 1 : 0) }
    function setPptPl1(v) { pptPl1 = Math.round(v); setArmouryAttr("ppt_pl1_spl", pptPl1) }
    function setPptPl2(v) { pptPl2 = Math.round(v); setArmouryAttr("ppt_pl2_sppt", pptPl2) }
    function setPptPl3(v) { pptPl3 = Math.round(v); setArmouryAttr("ppt_pl3_fppt", pptPl3) }
    function setNvDynBoost(v) { nvDynBoost = Math.round(v); setArmouryAttr("nv_dynamic_boost", nvDynBoost) }
    function setNvTempTarget(v) { nvTempTarget = Math.round(v); setArmouryAttr("nv_temp_target", nvTempTarget) }
    // Firmware ships a sane default per attribute; `asusctl armoury list`
    // reports it, so "Defaults" is just replaying those values.
    function restorePowerDefaults() {
        var d = root.armouryDefaults
        if (d.ppt_pl1_spl !== undefined) setPptPl1(d.ppt_pl1_spl)
        if (d.ppt_pl2_sppt !== undefined) setPptPl2(d.ppt_pl2_sppt)
        if (d.ppt_pl3_fppt !== undefined) setPptPl3(d.ppt_pl3_fppt)
        if (d.nv_dynamic_boost !== undefined) setNvDynBoost(d.nv_dynamic_boost)
        if (d.nv_temp_target !== undefined) setNvTempTarget(d.nv_temp_target)
    }

    // GPU mode — Eco/Standard/Ultimate collapse to the mux + dgpu_disable
    // pair. Only the attribute that actually changes is written, so an Eco
    // switch on a mux-less laptop is still a single valid call.
    function setGpuMode(id) {
        var def = Model.gpuModeDef(id)
        setEcoPending(gpuMux && id === "eco")
        if (armourySupported.gpuMux && (def.mux === 0) !== targetMux) {
            queuedMux = def.mux
            setArmouryAttr("gpu_mux_mode", def.mux)
            return
        }
        if (ecoPending) return
        if (armourySupported.dgpuDisable && (def.dgpuDisable === 1) !== targetDgpu) {
            queuedDgpu = def.dgpuDisable
            setArmouryAttr("dgpu_disable", def.dgpuDisable)
        }
    }

    function setEcoPending(on) {
        if (on === ecoPending) return
        ecoPending = on
        ecoMarkerProc.command = ["sh", "-c", on ? 'mkdir -p "$(dirname "$1")" && touch "$1"' : 'rm -f "$1"', "sh", ecoMarker]
        ecoMarkerProc.running = true
    }

    // Applying a refresh rate is two steps where hyprmoncfg is managing
    // displays: change it live, then persist it into the daemon's active
    // profile. Without that second step hyprmoncfgd re-applies its saved
    // profile a few seconds later and the change silently reverts. On a
    // machine without the daemon the first step alone is the whole job.
    function setRefreshRate(hz) {
        if (!monitor || displayProc.running || hyprmoncfgSaveProc.running) return
        displayProc.command = Model.monitorCommand(monitor, hz)
        displayProc.running = true
    }

    visible: asusctlAvailable
    implicitWidth: asusctlAvailable ? button.implicitWidth : 0
    implicitHeight: asusctlAvailable ? button.implicitHeight : 0

    BarIconButton {
        id: button; anchors.fill: parent; bar: root.bar
        text: Model.profileIcon(currentProfile); slotSize: Style.bar.iconSlot
        // Tooltip doubles as the at-a-glance sensor readout, so the common
        // "how hot is it right now" question needs no click at all.
        tooltipText: {
            var t = "ASUS — " + Model.profileLabel(root.currentProfile)
            if (root.sensors.cpuTemp >= 0) t += "\nCPU  " + Model.fmtTemp(root.sensors.cpuTemp) + "   " + Model.fmtRpm(root.sensors.fanCpu)
            if (root.nvidiaSleeping) t += "\nGPU  Sleeping"
            else if (root.sensors.gpuTemp >= 0) t += "\nGPU  " + Model.fmtTemp(root.sensors.gpuTemp) + "   " + Model.fmtRpm(root.sensors.fanGpu)
            return t
        }
        onPressed: function(b) { root.toggle() }
        // Scroll cycles profiles without opening the panel — the fastest path
        // to Silent/Turbo, and what `cycleProfile` was written for.
        onWheelMoved: function(delta) { root.cycleProfile(delta > 0 ? 1 : -1) }
    }

    KeyboardPanel {
        id: panel; anchorItem: root.anchorItem || button; owner: root; bar: root.bar
        open: root.opened && root.asusctlAvailable; focusTarget: keyCatcher
        // The Flickable inside is inset by `flickMargin` on every side, so the
        // panel has to be asked for that much extra in both axes — sizing it
        // to the raw content height clipped the final row of whichever tab was
        // showing (the last slider on Advanced, the overdrive toggle on Main).
        readonly property real flickMargin: Style.space(12)
        contentWidth: panel.fittedContentWidth(Style.space(360) + flickMargin * 2)
        contentHeight: panel.fittedContentHeight(scrollCol.implicitHeight + flickMargin * 2)

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: panel.flickMargin
            contentHeight: scrollCol.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: scrollCol
                width: parent.width
                spacing: Style.space(12)

                // TABS — no hero header; the bar icon + active tab already
                // identify the panel, so the title/profile line is dropped
                // to give tab content more room before it needs to scroll.
                Row {
                    id: tabRow
                    width: parent.width
                    spacing: Style.space(4)
                    readonly property real cellWidth: root.tabs.length > 0 ? (width - spacing * (root.tabs.length - 1)) / root.tabs.length : 0
                    Repeater {
                        model: root.tabs
                        Button {
                            required property var modelData
                            required property int index
                            width: tabRow.cellWidth
                            text: modelData.label
                            fontSize: Style.font.bodySmall
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            horizontalPadding: Style.spacing.controlPaddingX
                            verticalPadding: Style.spacing.controlPaddingY
                            bordered: true
                            active: root.tabIndex === index
                            onClicked: root.selectTab(index)
                        }
                    }
                }

                PanelSeparator { foreground: root.bar.foreground }

                // Last failed write (see showActionError). Above the tab bodies
                // so it shows whichever tab produced it, and clears itself.
                Text {
                    visible: root.actionError !== ""
                    width: parent.width
                    text: root.actionError
                    wrapMode: Text.WordWrap
                    color: "#ff8844"
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                }

                // Tab bodies are plain always-built Columns toggled by `visible`
                // rather than Loader/Component — Quickshell's incubator can take
                // multiple frames to finish building a freshly-activated Loader's
                // Component, which showed up as tab content intermittently
                // rendering blank/short right after opening. Building everything
                // up front as part of the panel's normal synchronous construction
                // avoids that race entirely.

                // ============================================================ MAIN TAB
                Column { visible: root.tabKey === "main"; width: parent.width; spacing: Style.space(12)

                    // LIVE SENSORS — G-Helper's home screen leads with temps
                    // and fan speeds, so this sits above the controls. Tiles
                    // for hardware that reports nothing stay hidden rather
                    // than showing a dash forever.
                    Grid {
                        id: sensorGrid
                        width: parent.width
                        columns: 2
                        spacing: Style.space(6)
                        readonly property real cw: (width - spacing) / 2

                        SensorTile {
                            width: sensorGrid.cw
                            caption: "CPU"
                            tip: "Package temperature and the CPU fan's current speed.\nSustained load on this laptop settles around 80–95 °C."
                            value: Model.fmtTemp(root.sensors.cpuTemp)
                            sub: Model.fmtRpm(root.sensors.fanCpu)
                            valueColor: Model.tempColor(root.sensors.cpuTemp)
                            foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                        }
                        SensorTile {
                            visible: root.hasNvidia
                            width: sensorGrid.cw
                            caption: "GPU"
                            tip: "Discrete GPU runtime state, temperature, fan speed, and utilisation.\nSleeping is detected through PCI sysfs without waking the dGPU."
                            value: root.nvidiaSleeping ? "Sleeping" : Model.fmtTemp(root.sensors.gpuTemp)
                            sub: root.nvidiaSleeping ? "dGPU runtime suspended" : Model.fmtRpm(root.sensors.fanGpu) + (root.sensors.gpuUtil >= 0 ? "   " + root.sensors.gpuUtil + "%" : "")
                            valueColor: Model.tempColor(root.sensors.gpuTemp)
                            foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                        }
                        SensorTile {
                            visible: root.sensors.batPct >= 0
                            width: sensorGrid.cw
                            caption: "BATTERY"
                            tip: "Charge level, whether it is charging, and the current\nflow in watts — draw when discharging, fill rate when charging."
                            value: root.sensors.batPct + "%"
                            sub: root.sensors.batStatus + (root.sensors.batPower > 0 ? "   " + Model.fmtWatts(root.sensors.batPower) : "")
                            valueColor: root.sensors.batPct <= 15 && root.sensors.batStatus !== "Charging" ? "#ff4444" : root.bar.foreground
                            foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                        }
                        SensorTile {
                            visible: root.hasNvidia && root.sensors.gpuPower >= 0
                            width: sensorGrid.cw
                            caption: "GPU POWER"
                            tip: "Watts the discrete GPU is currently drawing, and the\ndynamic boost ceiling set on the Advanced tab."
                            value: root.sensors.gpuPower + " W"
                            sub: "boost " + root.nvDynBoost + "W"
                            valueColor: root.bar.foreground
                            foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                        }
                    }

                    Column { width: parent.width; spacing: Style.space(8)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "PERFORMANCE MODE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Row { id: pRow; width: parent.width; spacing: Style.space(4); readonly property real cw: root.profiles.length > 0 ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length : 0
                            Repeater { model: root.profiles
                                Button { required property var modelData; required property int index; width: pRow.cw; iconText: Model.profileIcon(String(modelData)); iconSize: Style.font.title; text: String(modelData); tooltipText: Model.profileDescription(String(modelData)); fontSize: Style.font.bodySmall; foreground: root.currentProfile === modelData ? Model.profileColor(String(modelData)) : root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.currentProfile === modelData; hasCursor: root.cursorActive && root.profileIndex === index; onClicked: root.setProfile(modelData); onHovered: function(h) { if (h) { root.cursorActive = true; root.profileIndex = index } } }
                            }
                        }
                    }

                    // GPU MODE — Eco / Standard / Ultimate, mirroring G-Helper.
                    Column { visible: root.hasGpuMode; width: parent.width; spacing: Style.space(8)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "GPU MODE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Row { id: gRow; width: parent.width; spacing: Style.space(4); readonly property real cw: (width - spacing * 2) / 3
                            Repeater { model: Model.gpuModes
                                Button {
                                    required property var modelData
                                    width: gRow.cw
                                    // Ultimate needs the mux; hiding it outright would
                                    // shuffle the row, so it is disabled instead.
                                    enabled: modelData.id !== "ultimate" ? root.armourySupported.dgpuDisable || root.armourySupported.gpuMux : root.armourySupported.gpuMux
                                    opacity: enabled ? 1 : 0.4
                                    iconText: modelData.icon; iconSize: Style.font.title
                                    text: modelData.name
                                    tooltipText: enabled ? modelData.tip : modelData.tip + "\n\nNot available: this laptop has no MUX switch."
                                    fontSize: Style.font.bodySmall
                                    foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                                    horizontalPadding: Style.spacing.controlPaddingX
                                    verticalPadding: Style.spacing.controlPaddingY
                                    bordered: true
                                    active: root.gpuMode === modelData.id
                                    onClicked: root.setGpuMode(modelData.id)
                                }
                            }
                        }
                        Text { width: parent.width; text: Model.gpuModeDef(root.gpuMode).desc; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                        Text { visible: root.gpuRebootPending; width: parent.width; text: "\u{F0709}  Restart" + (root.ecoPending && root.gpuMux ? " twice" : "") + " to switch to " + Model.gpuModeDef(root.gpuMode).name + " (running " + Model.gpuModeDef(root.activeGpuMode).name + ")"; wrapMode: Text.WordWrap; color: "#cc9944"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                    }

                    // SCREEN — refresh rate comes from Hyprland, overdrive from
                    // asusctl; G-Helper pairs them in one control for the same
                    // reason (high refresh without OD looks smeary).
                    Column { visible: root.monitor !== null && root.monitor.rates.length > 1; width: parent.width; spacing: Style.space(8)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "SCREEN — " + (root.monitor ? root.monitor.name : "") + (root.hyprmoncfgManaged ? "  ·  " + root.hyprmoncfgProfile : ""); foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Row { id: hzRow; width: parent.width; spacing: Style.space(4); readonly property int n: root.monitor ? root.monitor.rates.length : 1; readonly property real cw: (width - spacing * (n - 1)) / Math.max(1, n)
                            Repeater { model: root.monitor ? root.monitor.rates : []
                                Button { required property var modelData; width: hzRow.cw; text: modelData + " Hz"; tooltipText: "Run " + (root.monitor ? root.monitor.name : "the panel") + " at " + modelData + " Hz.\n" + (modelData >= 90 ? "Smoother motion, noticeably more battery drain." : "Lower power draw, longer battery life.") + (root.hyprmoncfgManaged ? "\n\nSaved into the hyprmoncfg profile \"" + root.hyprmoncfgProfile + "\", so it sticks." : "\n\nApplied until the Hyprland config is reloaded."); fontSize: Style.font.bodySmall; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.monitor && root.monitor.rate === modelData; onClicked: root.setRefreshRate(modelData) }
                            }
                        }
                        Toggle {
                            id: odToggle
                            visible: root.armourySupported.panelOverdrive
                            width: parent.width
                            label: "Panel Overdrive"
                            description: "Faster pixel response at high refresh"
                            checked: root.panelOverdrive
                            foreground: root.bar.foreground; accent: Color.accent; fontFamily: root.bar.fontFamily
                            onClicked: root.togglePanelOverdrive()
                            // Toggle reports hover as a signal rather than a
                            // property, so the tooltip tracks it via a flag.
                            property bool tipHovered: false
                            onHovered: function(h) { odToggle.tipHovered = h }
                            PanelToolTip { visible: odToggle.tipHovered; text: Model.armouryTips.panel_overdrive }
                        }
                    }

                    Column { visible: root.supported.hasBattery && root.showBatteryLimit; width: parent.width; spacing: Style.space(8)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "BATTERY CHARGE LIMIT"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Row { width: parent.width; spacing: Style.space(4)
                            PanelSlider { width: parent.width - Style.space(44) - Style.space(4); bar: root.bar; minimum: 20; maximum: 100; step: 5; integer: true; value: root.batteryLimit; tickCount: 9; onReleased: function(v) { root.setBatteryLimit(Math.round(v)) } }
                            Text { text: root.batteryLimit + "%"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; font.bold: true; width: Style.space(44); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row { width: parent.width; spacing: Style.space(4)
                            Repeater { model: [20, 40, 60, 80, 100]
                                Button { required property var modelData; width: (parent.width - Style.space(4) * 4) / 5; text: modelData + "%"; tooltipText: modelData === 100 ? "Charge to full.\nConvenient, but hardest on long-term battery health." : "Stop charging at " + modelData + "%.\nLower limits slow battery wear; 60–80% suits a mostly plugged-in laptop."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.batteryLimit === modelData; onClicked: root.setBatteryLimit(modelData) }
                            }
                        }
                        // One-shot: charge to a chosen level once. asusd's own
                        // one-shot only ever charges to 100%, so the panel sets
                        // the limit to the target and restores the limit above as
                        // soon as the battery arrives.
                        Row { width: parent.width; spacing: Style.space(4)
                            Text { text: "One-shot"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(52); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: oneshotHelp; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                PanelToolTip { visible: oneshotHelp.containsMouse; text: "Charge to the target once, then restore the limit above.\nWhile it runs, charging is capped at the target\nand the button becomes Stop." }
                            }
                            PanelSlider { width: parent.width - Style.space(52) - Style.space(34) - Style.space(56) - Style.space(4) * 3; bar: root.bar; minimum: 20; maximum: 100; step: 5; integer: true; value: root.oneshotTarget; onReleased: function(v) { root.oneshotTarget = Math.round(v) } }
                            Text { text: root.oneshotTarget + "%"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(34); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            Button { id: oneshotBtn; width: Style.space(56); text: root.oneshotActive ? "Stop" : "Charge"; tooltipText: root.oneshotActive ? "Stop the one-shot and put the limit back to " + root.oneshotPlan.restore + "%." : "Charge to " + root.oneshotTarget + "% once, then restore the limit above."; fontSize: Style.font.caption; foreground: root.oneshotActive ? "#ff8844" : root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; anchors.verticalCenter: parent.verticalCenter; onClicked: root.oneshotActive ? root.stopOneshot() : root.startOneshot(root.oneshotTarget) }
                        }
                    }
                }

                // ============================================================= RGB TAB
                Column { visible: root.tabKey === "rgb"; width: parent.width; spacing: Style.space(8)
                    // Header with LED toggle
                    Row { width: parent.width
                        Text { text: "KEYBOARD RGB"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - ledSw.width - Style.space(8) }
                        Row { id: ledSw; spacing: Style.space(4); anchors.verticalCenter: parent.verticalCenter
                            Rectangle { width: Style.space(14); height: Style.space(14); radius: Style.space(7); color: root.keyboardLit ? "#44cc44" : "#cc4444"; anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity { running: root.keyboardLit; loops: Animation.Infinite; NumberAnimation { from: 1; to: 0.5; duration: 800 } NumberAnimation { from: 0.5; to: 1; duration: 800 } }
                            }
                            Text { text: root.keyboardLit ? "ON" : "OFF"; color: root.keyboardLit ? "#44cc44" : "#cc4444"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            MouseArea { id: ledPowerMouse; width: Style.space(40); height: Style.space(20); anchors.verticalCenter: parent.verticalCenter; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleKeyboardPower()
                                PanelToolTip { visible: ledPowerMouse.containsMouse; text: root.keyboardLit ? "Keyboard lighting is on. Click to turn it off." : "Keyboard lighting is off. Click to turn it on." }
                            }
                        }
                    }
                    // Effect grid — only modes this laptop's asusctl actually reports supporting.
                    Grid { width: parent.width; columns: 3; spacing: Style.space(3)
                        Repeater { model: root.auraSupportedEffects
                            Rectangle { required property var modelData; width: (parent.width - Style.space(3) * 2) / 3; height: Style.space(40); radius: Style.cornerRadius; color: root.currentEffect === modelData.id ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.2) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.06); border.width: root.currentEffect === modelData.id ? 2 : 1; border.color: root.currentEffect === modelData.id ? root.bar.foreground : "transparent"
                                Row { anchors.centerIn: parent; spacing: Style.space(4)
                                    Text { text: modelData.icon; color: root.currentEffect === modelData.id ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.body }
                                    Text { text: modelData.name; color: root.currentEffect === modelData.id ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { id: fxMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectEffect(modelData.id) }
                                PanelToolTip { visible: fxMouse.containsMouse; text: modelData.tip }
                            }
                        }
                    }
                    // Effect params
                    Column { visible: root.needsColor || root.needsColor2 || root.needsSpeed || root.needsDirection; width: parent.width; spacing: Style.space(6)
                        Column { visible: root.needsColor; width: parent.width; spacing: Style.space(4)
                            Row { width: parent.width; spacing: Style.space(6)
                                Rectangle { width: Style.space(20); height: Style.space(20); radius: Style.space(10); color: root.liveColor; border.width: 1; border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.3); anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Color  #" + root.colorHex.toUpperCase(); color: root.bar.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                                Item { width: parent.width - Style.space(20) - Style.space(60) - Style.space(6) * 2; height: 1 }
                                Button { text: "Set"; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: true; anchors.verticalCenter: parent.verticalCenter; onClicked: root.applyEffect() }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "R"; color: "#ff4444"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.colorR; fillColor: Qt.rgba(1, 0.2, 0.2, 1); knobColor: Qt.rgba(1, 0.3, 0.3, 1); onReleased: function(v) { root.colorR = Math.round(v) } }
                                Text { text: root.colorR; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "G"; color: "#44cc44"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.colorG; fillColor: Qt.rgba(0.2, 1, 0.2, 1); knobColor: Qt.rgba(0.3, 1, 0.3, 1); onReleased: function(v) { root.colorG = Math.round(v) } }
                                Text { text: root.colorG; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "B"; color: "#4488ff"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.colorB; fillColor: Qt.rgba(0.2, 0.2, 1, 1); knobColor: Qt.rgba(0.3, 0.3, 1, 1); onReleased: function(v) { root.colorB = Math.round(v) } }
                                Text { text: root.colorB; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                        Column { visible: root.needsColor2; width: parent.width; spacing: Style.space(4)
                            Row { width: parent.width; spacing: Style.space(6)
                                Rectangle { width: Style.space(20); height: Style.space(20); radius: Style.space(10); color: root.liveColor2; border.width: 1; border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.3); anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Color 2  #" + root.color2Hex.toUpperCase(); color: root.bar.foreground; font.family: "monospace"; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "R"; color: "#ff4444"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.color2R; fillColor: Qt.rgba(1, 0.2, 0.2, 1); knobColor: Qt.rgba(1, 0.3, 0.3, 1); onReleased: function(v) { root.color2R = Math.round(v) } }
                                Text { text: root.color2R; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "G"; color: "#44cc44"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.color2G; fillColor: Qt.rgba(0.2, 1, 0.2, 1); knobColor: Qt.rgba(0.3, 1, 0.3, 1); onReleased: function(v) { root.color2G = Math.round(v) } }
                                Text { text: root.color2G; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Row { width: parent.width; spacing: Style.space(4)
                                Text { text: "B"; color: "#4488ff"; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(12); anchors.verticalCenter: parent.verticalCenter }
                                PanelSlider { width: parent.width - Style.space(12) - Style.space(24) - Style.space(4) * 2; bar: root.bar; minimum: 0; maximum: 255; step: 1; integer: true; value: root.color2B; fillColor: Qt.rgba(0.2, 0.2, 1, 1); knobColor: Qt.rgba(0.3, 0.3, 1, 1); onReleased: function(v) { root.color2B = Math.round(v) } }
                                Text { text: root.color2B; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(24); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                        Row { visible: root.needsSpeed; width: parent.width; spacing: Style.space(4)
                            Text { text: "Speed"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter; width: Style.space(40) }
                            Repeater { model: Model.speeds
                                Button { required property var modelData; width: (parent.width - Style.space(40) - Style.space(4) * 2) / 3; text: Model.speedLabels[modelData]; tooltipText: "How fast the " + root.effectDef.name + " effect animates."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.currentSpeed === modelData; onClicked: { root.currentSpeed = modelData; root.applyEffect() } }
                            }
                        }
                        Row { visible: root.needsDirection; width: parent.width; spacing: Style.space(4)
                            Text { text: "Dir"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter; width: Style.space(40) }
                            Repeater { model: Model.directions
                                Button { required property var modelData; width: (parent.width - Style.space(40) - Style.space(4) * 3) / 4; text: modelData.charAt(0).toUpperCase() + modelData.slice(1); tooltipText: "Animate the effect towards the " + modelData + "."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.currentDirection === modelData; onClicked: { root.currentDirection = modelData; root.applyEffect() } }
                            }
                        }
                        Grid { visible: root.needsColor; width: parent.width; columns: 6; spacing: Style.space(3)
                            Repeater {
                                model: ["ff0000", "ff8800", "ffff00", "00ff00", "00ffff", "0088ff", "aa00ff", "ff00ff", "ffffff", "ffaa44", "44ccff", "88ff00"]
                                Rectangle {
                                    required property string modelData
                                    property color swatchColor: Qt.rgba(
                                        parseInt(modelData.substring(0, 2), 16) / 255,
                                        parseInt(modelData.substring(2, 4), 16) / 255,
                                        parseInt(modelData.substring(4, 6), 16) / 255,
                                        1
                                    )
                                    width: (parent.width - Style.space(3) * 5) / 6
                                    height: Style.space(22)
                                    radius: Style.space(4)
                                    color: swatchColor
                                    border.width: root.colorHex === modelData ? 2 : 1
                                    border.color: root.colorHex === modelData ? root.bar.foreground : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.15)
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setPresetColor(modelData) }
                                }
                            }
                        }
                    }
                    // LED Brightness
                    Column { width: parent.width; spacing: Style.space(4)
                        Text { text: "LED Brightness"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Row { width: parent.width; spacing: Style.space(4)
                            Repeater { model: ["off", "low", "med", "high"]
                                Button { required property var modelData; width: (parent.width - Style.space(4) * 3) / 4; text: modelData.charAt(0).toUpperCase() + modelData.slice(1); tooltipText: modelData === "off" ? "Turn the keyboard backlight off entirely." : "Set keyboard backlight brightness to " + modelData + "."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.ledBrightness === modelData; onClicked: root.setLedBrightness(modelData) }
                            }
                        }
                    }

                    // Per-zone aura power (newer 2021+ keyboards). Each zone the
                    // laptop reports gets its own row of power-state switches;
                    // zones the hardware lacks never appear, which is what keeps
                    // this section honest on a TUF that only exposes Keyboard.
                    Column { visible: root.auraPowerZones.length > 0; width: parent.width; spacing: Style.space(6)
                        PanelSeparator { foreground: root.bar.foreground }
                        Text { text: "Aura power zones"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Repeater {
                            model: root.auraPowerZones
                            Column {
                                id: zoneCol
                                required property string modelData
                                readonly property string zoneName: modelData
                                width: parent.width; spacing: Style.space(3)
                                Text { text: Model.auraZoneLabel(zoneCol.zoneName); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                                Row { id: zoneRow; width: parent.width; spacing: Style.space(4)
                                    readonly property real cw: (width - spacing * (Model.auraPowerStates.length - 1)) / Model.auraPowerStates.length
                                    Repeater {
                                        model: Model.auraPowerStates
                                        Button {
                                            required property string modelData
                                            width: zoneRow.cw
                                            text: Model.auraStateLabels[modelData]
                                            tooltipText: "Power the " + Model.auraZoneLabel(zoneCol.zoneName) + " zone during the \"" + Model.auraStateLabels[modelData] + "\" state."
                                            fontSize: Style.font.caption
                                            foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                                            horizontalPadding: Style.spacing.controlPaddingX
                                            verticalPadding: Style.spacing.controlPaddingY
                                            bordered: true
                                            active: root.auraPowerOn(zoneCol.zoneName, modelData)
                                            onClicked: root.setAuraPower(zoneCol.zoneName, modelData, !root.auraPowerOn(zoneCol.zoneName, modelData))
                                        }
                                    }
                                }
                            }
                        }
                        Text { width: parent.width; text: "asusctl does not report these back, so they show what this panel last set."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                    }

                    // Legacy power-tuf states — old ROG/TUF models that report no
                    // aura power zones. asusctl takes these in one call, so each
                    // toggle resends the whole set (see applyLedPower).
                    Column { visible: root.auraPowerZones.length === 0; width: parent.width; spacing: Style.space(4)
                        PanelSeparator { foreground: root.bar.foreground }
                        Text { text: "Lighting active while"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Row { width: parent.width; spacing: Style.space(4)
                            Button { width: (parent.width - Style.space(4) * 2) / 3; text: "Awake"; tooltipText: "Keep the keyboard lit while the laptop is in normal use."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.ledAwake; onClicked: root.setLedPower(!root.ledAwake) }
                            Button { width: (parent.width - Style.space(4) * 2) / 3; text: "Boot"; tooltipText: "Play the lighting animation during power-on and shutdown."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.ledBoot; onClicked: root.setLedBoot(!root.ledBoot) }
                            Button { width: (parent.width - Style.space(4) * 2) / 3; text: "Sleep"; tooltipText: "Keep a breathing light going while the laptop is suspended."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.ledSleep; onClicked: root.setLedSleep(!root.ledSleep) }
                        }
                        Text { width: parent.width; text: "asusctl does not report these back, so they show what this panel last set."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                    }
                }

                // ============================================================= FAN TAB
                Column { visible: root.tabKey === "fan"; width: parent.width; spacing: Style.space(10)

                    Row { width: parent.width
                        Text { text: "CUSTOM FAN CURVES"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - masterSw.width - resetAllBtn.width - Style.space(16) }
                        Rectangle { id: masterSw; width: Style.space(48); height: Style.space(20); radius: Style.space(10); anchors.verticalCenter: parent.verticalCenter; color: root.fanCurveEnabled ? Qt.rgba(0.27, 0.8, 0.27, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
                            MouseArea { id: masterSwMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.profileLoaded; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleFanCurves() }
                            PanelToolTip { visible: masterSwMouse.containsMouse; text: "Master switch for custom fan curves.\nOff means the firmware's own curves run instead." }
                            Text { text: root.fanCurveEnabled ? "ON" : "OFF"; color: root.fanCurveEnabled ? "#44cc44" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                        }
                        Button { id: resetAllBtn; text: "Reset all"; tooltipText: "Restore the firmware's default fan curves\nfor the profile selected below."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; anchors.verticalCenter: parent.verticalCenter; anchors.leftMargin: Style.space(6); onClicked: root.resetFanCurves() }
                    }
                    Text { visible: !root.fanCurveEnabled; width: parent.width; text: "Turn this on to enable per-fan custom curves below."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }

                    // Curves are stored per power profile. Editing whichever
                    // profile is active is rarely what you want when tuning,
                    // so the target is picked explicitly here.
                    Column { width: parent.width; spacing: Style.space(4)
                        Text { text: "Editing curves for"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Row { id: fpRow; width: parent.width; spacing: Style.space(4); readonly property real cw: root.profiles.length > 0 ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length : 0
                            Repeater { model: root.profiles
                                Button { required property var modelData; width: fpRow.cw; text: String(modelData) + (root.currentProfile === modelData ? " •" : ""); tooltipText: "Edit the fan curves stored for the " + modelData + " profile." + (root.currentProfile === modelData ? "\nThis is the profile currently active (•)." : "\nChanges apply when you switch to that profile."); fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; active: root.fanProfile === modelData; onClicked: root.selectFanProfile(String(modelData)) }
                            }
                        }
                    }

                    // CPU Fan
                    Column { width: parent.width; spacing: Style.space(4); opacity: root.fanCurveEnabled ? 1 : 0.5
                        Row { width: parent.width; spacing: Style.space(8)
                            Rectangle { width: Style.space(12); height: Style.space(12); radius: Style.space(6); color: root.cpuFanEnabled ? "#44cc44" : "#666"; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "CPU Fan"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: Model.fmtRpm(root.sensors.fanCpu) + "   " + Model.fmtTemp(root.sensors.cpuTemp); color: Qt.darker(root.bar.foreground, 1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; width: parent.width - Style.space(12) - Style.space(48) - Style.space(70) }
                            Rectangle { width: Style.space(48); height: Style.space(20); radius: Style.space(10); color: root.cpuFanEnabled ? Qt.rgba(0.27, 0.8, 0.27, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: cpuSwMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.fanCurveEnabled; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleCpuFan() }
                                PanelToolTip { visible: cpuSwMouse.containsMouse; text: "Use the custom curve below for the CPU fan." }
                                Text { text: root.cpuFanEnabled ? "ON" : "OFF"; color: root.cpuFanEnabled ? "#44cc44" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                            }
                        }
                        FanCurveEditor {
                            width: parent.width
                            points: root.cpuFanPoints
                            enabledState: root.cpuFanEnabled
                            interactive: root.fanCurveEnabled
                            accent: "#44cc44"
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            onCommit: function(pts) { root.cpuFanPoints = pts; root.applyFanCurve("cpu", pts) }
                            onReset: root.resetFanCurves()
                        }
                    }
                    // GPU Fan
                    Column { width: parent.width; spacing: Style.space(4); opacity: root.fanCurveEnabled ? 1 : 0.5
                        Row { width: parent.width; spacing: Style.space(8)
                            Rectangle { width: Style.space(12); height: Style.space(12); radius: Style.space(6); color: root.gpuFanEnabled ? "#4488ff" : "#666"; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "GPU Fan"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: Model.fmtRpm(root.sensors.fanGpu) + (root.sensors.gpuTemp >= 0 ? "   " + Model.fmtTemp(root.sensors.gpuTemp) : ""); color: Qt.darker(root.bar.foreground, 1.5); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; width: parent.width - Style.space(12) - Style.space(48) - Style.space(70) }
                            Rectangle { width: Style.space(48); height: Style.space(20); radius: Style.space(10); color: root.gpuFanEnabled ? Qt.rgba(0.27, 0.53, 1, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: gpuSwMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.fanCurveEnabled; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleGpuFan() }
                                PanelToolTip { visible: gpuSwMouse.containsMouse; text: "Use the custom curve below for the GPU fan." }
                                Text { text: root.gpuFanEnabled ? "ON" : "OFF"; color: root.gpuFanEnabled ? "#4488ff" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                            }
                        }
                        FanCurveEditor {
                            width: parent.width
                            points: root.gpuFanPoints
                            enabledState: root.gpuFanEnabled
                            interactive: root.fanCurveEnabled
                            accent: "#4488ff"
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            onCommit: function(pts) { root.gpuFanPoints = pts; root.applyFanCurve("gpu", pts) }
                            onReset: root.resetFanCurves()
                        }
                    }
                    // Mid Fan — only laptops with a third fan report this.
                    Column { visible: root.hasMidFan; width: parent.width; spacing: Style.space(4); opacity: root.fanCurveEnabled ? 1 : 0.5
                        Row { width: parent.width; spacing: Style.space(8)
                            Rectangle { width: Style.space(12); height: Style.space(12); radius: Style.space(6); color: root.midFanEnabled ? "#cc9944" : "#666"; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Mid Fan"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(60) }
                            Rectangle { width: Style.space(48); height: Style.space(20); radius: Style.space(10); color: root.midFanEnabled ? Qt.rgba(0.8, 0.6, 0.27, 0.3) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: midSwMouse; anchors.fill: parent; hoverEnabled: true; enabled: root.fanCurveEnabled; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMidFan() }
                                PanelToolTip { visible: midSwMouse.containsMouse; text: "Use the custom curve below for the middle fan." }
                                Text { text: root.midFanEnabled ? "ON" : "OFF"; color: root.midFanEnabled ? "#cc9944" : Qt.darker(root.bar.foreground, 1.6); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.centerIn: parent }
                            }
                        }
                        FanCurveEditor {
                            width: parent.width
                            points: root.midFanPoints
                            enabledState: root.midFanEnabled
                            interactive: root.fanCurveEnabled
                            accent: "#cc9944"
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            onCommit: function(pts) { root.midFanPoints = pts; root.applyFanCurve("mid", pts) }
                            onReset: root.resetFanCurves()
                        }
                    }
                }

                // ======================================================== ADVANCED TAB
                Column { visible: root.tabKey === "advanced"; width: parent.width; spacing: Style.space(8)
                    Row { width: parent.width
                        Text { width: parent.width - defaultsBtn.width - Style.space(8); text: "Firmware power limits, CPU boost, and the daemons behind them. Only the controls this laptop actually reports are shown."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                        Button { id: defaultsBtn; text: "Defaults"; tooltipText: "Put every power limit below back to the value\nthe firmware reports as its default."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; anchors.verticalCenter: parent.verticalCenter; onClicked: root.restorePowerDefaults() }
                    }
                    Column { visible: root.armourySupported.pptPl1 || root.armourySupported.pptPl2 || root.armourySupported.pptPl3; width: parent.width; spacing: Style.space(4)
                        Text { text: "CPU Power"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Row { visible: root.armourySupported.pptPl1; width: parent.width; spacing: Style.space(4)
                            Text { text: "PL1"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: pl1Help; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                PanelToolTip { visible: pl1Help.containsMouse; text: Model.armouryTips.ppt_pl1_spl }
                            }
                            PanelSlider { width: parent.width - Style.space(40) - Style.space(32) - Style.space(4) * 2 - Style.space(48); bar: root.bar; minimum: root.pptPl1Min; maximum: root.pptPl1Max; step: 1; integer: true; value: root.pptPl1; onReleased: function(v) { root.setPptPl1(v) } }
                            Text { text: root.pptPl1 + "W"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row { visible: root.armourySupported.pptPl2; width: parent.width; spacing: Style.space(4)
                            Text { text: "PL2"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: pl2Help; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                PanelToolTip { visible: pl2Help.containsMouse; text: Model.armouryTips.ppt_pl2_sppt }
                            }
                            PanelSlider { width: parent.width - Style.space(40) - Style.space(32) - Style.space(4) * 2 - Style.space(48); bar: root.bar; minimum: root.pptPl2Min; maximum: root.pptPl2Max; step: 1; integer: true; value: root.pptPl2; onReleased: function(v) { root.setPptPl2(v) } }
                            Text { text: root.pptPl2 + "W"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row { visible: root.armourySupported.pptPl3; width: parent.width; spacing: Style.space(4)
                            Text { text: "PL3"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: pl3Help; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                PanelToolTip { visible: pl3Help.containsMouse; text: Model.armouryTips.ppt_pl3_fppt }
                            }
                            PanelSlider { width: parent.width - Style.space(40) - Style.space(32) - Style.space(4) * 2 - Style.space(48); bar: root.bar; minimum: root.pptPl3Min; maximum: root.pptPl3Max; step: 1; integer: true; value: root.pptPl3; onReleased: function(v) { root.setPptPl3(v) } }
                            Text { text: root.pptPl3 + "W"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Column { visible: root.armourySupported.nvDynBoost || root.armourySupported.nvTempTarget; width: parent.width; spacing: Style.space(4)
                        Text { text: "GPU Power"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                        Row { visible: root.armourySupported.nvDynBoost; width: parent.width; spacing: Style.space(4)
                            Text { text: "Boost"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: boostHelp; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                PanelToolTip { visible: boostHelp.containsMouse; text: Model.armouryTips.nv_dynamic_boost }
                            }
                            PanelSlider { width: parent.width - Style.space(40) - Style.space(32) - Style.space(4) * 2 - Style.space(48); bar: root.bar; minimum: root.nvDynBoostMin; maximum: root.nvDynBoostMax; step: 1; integer: true; value: root.nvDynBoost; onReleased: function(v) { root.setNvDynBoost(v) } }
                            Text { text: root.nvDynBoost + "W"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                        Row { visible: root.armourySupported.nvTempTarget; width: parent.width; spacing: Style.space(4)
                            Text { text: "Temp"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter
                                MouseArea { id: tempHelp; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                PanelToolTip { visible: tempHelp.containsMouse; text: Model.armouryTips.nv_temp_target }
                            }
                            PanelSlider { width: parent.width - Style.space(40) - Style.space(32) - Style.space(4) * 2 - Style.space(48); bar: root.bar; minimum: root.nvTempTargetMin; maximum: root.nvTempTargetMax; step: 1; integer: true; value: root.nvTempTarget; onReleased: function(v) { root.setNvTempTarget(v) } }
                            Text { text: root.nvTempTarget + "°C"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(32); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    // CPU BOOST — a sysfs flag rather than a firmware attribute,
                    // so it sits outside the "Defaults" group above, and it is
                    // hidden entirely on a machine with no boost switch.
                    Column { visible: root.turbo.available; width: parent.width; spacing: Style.space(6)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "CPU BOOST"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Toggle {
                            id: turboToggle
                            width: parent.width
                            label: "Turbo Boost"
                            description: root.turbo.enabled ? "On — the CPU may clock above its base frequency" : "Off — the CPU is capped at its base frequency"
                            checked: root.turbo.enabled
                            foreground: root.bar.foreground; accent: Color.accent; fontFamily: root.bar.fontFamily
                            onClicked: root.toggleTurbo()
                            property bool tipHovered: false
                            onHovered: function(h) { turboToggle.tipHovered = h }
                            PanelToolTip { visible: turboToggle.tipHovered; text: "asusctl exposes no boost switch, so this writes " + Model.turboPath(root.turbo.kind) + "\nthrough pkexec. Turning it off lowers peak and sustained\ntemperatures at the cost of burst performance.\nNeeds the polkit rule from the README, otherwise the prompt\nis cancelled and nothing changes." }
                        }
                    }
                    // AUTO-SWITCH ON POWER — saves a mode per source and applies it
                    // when the charger is plugged or unplugged. Persisted in
                    // shell.json through `omarchy bar set`.
                    Column { visible: root.supported.hasProfile; width: parent.width; spacing: Style.space(8)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "AUTO-SWITCH ON POWER"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Repeater {
                            model: [{ key: "ac", label: "Plugged in" }, { key: "battery", label: "On battery" }]
                            Column {
                                id: presetBlock
                                required property var modelData
                                width: parent.width; spacing: Style.space(3)
                                Text { text: presetBlock.modelData.label; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                                Row { id: presetRow; width: parent.width; spacing: Style.space(4)
                                    readonly property real cw: (width - spacing * 3) / 4
                                    Repeater {
                                        model: ["Auto", "Quiet", "Balanced", "Performance"]
                                        Button {
                                            required property string modelData
                                            width: presetRow.cw
                                            text: modelData
                                            tooltipText: modelData === "Auto"
                                                ? "Do not switch automatically; leave the " + (presetBlock.modelData.key === "battery" ? "battery" : "AC") + " mode as asusd has it."
                                                : "Apply " + modelData + " automatically when the charger is " + (presetBlock.modelData.key === "battery" ? "unplugged." : "plugged in.")
                                            fontSize: Style.font.caption
                                            foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                                            horizontalPadding: Style.spacing.controlPaddingX
                                            verticalPadding: Style.spacing.controlPaddingY
                                            bordered: true
                                            active: root.defaultProfileFor(presetBlock.modelData.key) === modelData
                                            onClicked: root.setDefaultProfile(presetBlock.modelData.key, modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // LID & HIBERNATE — system-wide systemd settings (logind's
                    // HandleLidSwitch and sleep.conf's HibernateDelaySec), written
                    // as drop-ins. Plans below can override them. Needs the polkit
                    // rule in the README; without it each change prompts.
                    Column { visible: root.supported.hasProfile; width: parent.width; spacing: Style.space(6)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "LID & HIBERNATE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Text { width: parent.width; text: "What closing the lid does, and how long a suspend waits before hibernating. Plans can override these."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                        Dropdown {
                            id: globalLidDropdown
                            width: parent.width
                            label: "Lid action"
                            value: root.globalLidValue()
                            options: Model.lidActionsGlobal.map(function(a) { return ({ value: a, label: Model.lidActionLabel(a) }) })
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            onChanged: function(v) { root.setLidAction(v) }
                        }
                        Column { width: parent.width; spacing: Style.space(3)
                            Text { text: "Auto hibernate after"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                            Row { id: globalHibRow; width: parent.width; spacing: Style.space(4)
                                readonly property string state: root.globalHibValue()
                                readonly property bool auto: state === "auto"
                                Button { width: Style.space(40); text: "Auto"; active: globalHibRow.auto; tooltipText: globalHibRow.auto ? "Auto — leave the hibernate delay at systemd's default. Click for a fixed value." : "Click to leave the hibernate delay at systemd's default."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; anchors.verticalCenter: parent.verticalCenter; onClicked: root.setHibDelay(globalHibRow.auto ? "60min" : "auto") }
                                PanelSlider { width: parent.width - Style.space(40) - Style.space(56) - Style.space(4) * 2; bar: root.bar; minimum: 15; maximum: 180; step: 15; integer: true; value: root.hibValueMinutes(globalHibRow.state); onReleased: function(v) { root.setHibDelay(root.hibValueFromSlider(v)) } }
                                Text { text: root.hibValueLabel(globalHibRow.state); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(56); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                    // POWER PLAN — one place to edit everything a single mode
                    // (Quiet/Balanced/Performance) carries. The dropdown picks the
                    // mode; the rows below edit that mode's screen refresh and CPU
                    // boost. Switching to the mode is what applies them.
                    Column { visible: root.supported.hasProfile; width: parent.width; spacing: Style.space(6)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "POWER PLAN"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Text { width: parent.width; text: "Pick a plan to edit everything it carries. The settings apply when you switch to that plan."; wrapMode: Text.WordWrap; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
                        Dropdown {
                            id: planDropdown
                            width: parent.width
                            label: "Plan"
                            value: root.plan
                            options: root.profiles
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            onChanged: function(v) { root.planKey = v }
                        }
                        // Screen refresh for the selected plan.
                        Column { visible: root.monitor !== null && root.monitor.rates.length > 1; width: parent.width; spacing: Style.space(3)
                            Text { text: "Screen refresh"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                            Row { id: planHzRow; width: parent.width; spacing: Style.space(4)
                                readonly property int n: 1 + (root.monitor ? root.monitor.rates.length : 0)
                                readonly property real cw: (width - spacing * (n - 1)) / Math.max(1, n)
                                Repeater {
                                    model: ["Auto"].concat(root.monitor ? root.monitor.rates : [])
                                    Button {
                                        required property var modelData
                                        width: planHzRow.cw
                                        text: modelData === "Auto" ? "Auto" : modelData + " Hz"
                                        tooltipText: modelData === "Auto"
                                            ? "Leave the refresh rate unchanged when switching to " + root.plan + "."
                                            : "Switch the screen to " + modelData + " Hz when switching to " + root.plan + "."
                                        fontSize: Style.font.caption
                                        foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                                        horizontalPadding: Style.spacing.controlPaddingX
                                        verticalPadding: Style.spacing.controlPaddingY
                                        bordered: true
                                        active: String(root.profileRefreshFor(root.plan)) === String(modelData)
                                        onClicked: root.setProfileRefresh(root.plan, String(modelData))
                                    }
                                }
                            }
                        }
                        // CPU boost for the selected plan.
                        Column { visible: root.turbo.available; width: parent.width; spacing: Style.space(3)
                            Text { text: "CPU boost"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                            Row { id: planBoostRow; width: parent.width; spacing: Style.space(4)
                                readonly property real cw: (width - spacing * 2) / 3
                                Repeater {
                                    model: ["Auto", "On", "Off"]
                                    Button {
                                        required property string modelData
                                        width: planBoostRow.cw
                                        text: modelData
                                        tooltipText: modelData === "Auto"
                                            ? "Leave boost as it is when switching to " + root.plan + "."
                                            : "Turn CPU boost " + modelData.toLowerCase() + " when switching to " + root.plan + "."
                                        fontSize: Style.font.caption
                                        foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                                        horizontalPadding: Style.spacing.controlPaddingX
                                        verticalPadding: Style.spacing.controlPaddingY
                                        bordered: true
                                        active: root.profileBoostFor(root.plan) === modelData
                                        onClicked: root.setProfileBoost(root.plan, modelData)
                                    }
                                }
                            }
                        }
                        // Per-plan firmware limits, grouped CPU/GPU the same way
                        // as the global limits above. Auto leaves a limit
                        // unchanged when switching to this plan.
                        Column { visible: root.armourySupported.pptPl1 || root.armourySupported.pptPl2 || root.armourySupported.pptPl3; width: parent.width; spacing: Style.space(3)
                            Text { text: "CPU Power"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                            Repeater {
                                model: root.planCpuLimitRows()
                                Row {
                                    id: cpuLimitRow
                                    required property var modelData
                                    visible: cpuLimitRow.modelData.supported
                                    width: parent.width; spacing: Style.space(4)
                                    readonly property string state: root.planLimitValue(root.plan, cpuLimitRow.modelData.key)
                                    readonly property bool auto: state === "Auto"
                                    readonly property int shown: auto ? cpuLimitRow.modelData.fallback : Number(state)
                                    Text { text: cpuLimitRow.modelData.label; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter }
                                    Button { width: Style.space(40); text: "Auto"; active: cpuLimitRow.auto; tooltipText: (cpuLimitRow.auto ? "Auto — this plan leaves " : "Click to leave ") + cpuLimitRow.modelData.label + (cpuLimitRow.auto ? " unchanged. Click for a fixed value." : " unchanged when switching to " + root.plan + "."); fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; anchors.verticalCenter: parent.verticalCenter; onClicked: root.togglePlanLimitAuto(root.plan, cpuLimitRow.modelData.key, cpuLimitRow.modelData.fallback) }
                                    PanelSlider { width: cpuLimitRow.width - Style.space(40) - Style.space(40) - Style.space(36) - Style.space(4) * 3 - Style.space(48); bar: root.bar; minimum: cpuLimitRow.modelData.minimum; maximum: cpuLimitRow.modelData.maximum; step: 1; integer: true; value: cpuLimitRow.shown; onReleased: function(v) { root.setPlanLimit(root.plan, cpuLimitRow.modelData.key, Math.round(v)) } }
                                    Text { text: cpuLimitRow.auto ? "Auto" : cpuLimitRow.shown + cpuLimitRow.modelData.unit; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(36); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                                }
                            }
                        }
                        Column { visible: root.armourySupported.nvDynBoost || root.armourySupported.nvTempTarget; width: parent.width; spacing: Style.space(3)
                            Text { text: "GPU Power"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                            Repeater {
                                model: root.planGpuLimitRows()
                                Row {
                                    id: gpuLimitRow
                                    required property var modelData
                                    visible: gpuLimitRow.modelData.supported
                                    width: parent.width; spacing: Style.space(4)
                                    readonly property string state: root.planLimitValue(root.plan, gpuLimitRow.modelData.key)
                                    readonly property bool auto: state === "Auto"
                                    readonly property int shown: auto ? gpuLimitRow.modelData.fallback : Number(state)
                                    Text { text: gpuLimitRow.modelData.label; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; width: Style.space(40); anchors.verticalCenter: parent.verticalCenter }
                                    Button { width: Style.space(40); text: "Auto"; active: gpuLimitRow.auto; tooltipText: (gpuLimitRow.auto ? "Auto — this plan leaves " : "Click to leave ") + gpuLimitRow.modelData.label + (gpuLimitRow.auto ? " unchanged. Click for a fixed value." : " unchanged when switching to " + root.plan + "."); fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; anchors.verticalCenter: parent.verticalCenter; onClicked: root.togglePlanLimitAuto(root.plan, gpuLimitRow.modelData.key, gpuLimitRow.modelData.fallback) }
                                    PanelSlider { width: gpuLimitRow.width - Style.space(40) - Style.space(40) - Style.space(36) - Style.space(4) * 3 - Style.space(48); bar: root.bar; minimum: gpuLimitRow.modelData.minimum; maximum: gpuLimitRow.modelData.maximum; step: 1; integer: true; value: gpuLimitRow.shown; onReleased: function(v) { root.setPlanLimit(root.plan, gpuLimitRow.modelData.key, Math.round(v)) } }
                                    Text { text: gpuLimitRow.auto ? "Auto" : gpuLimitRow.shown + gpuLimitRow.modelData.unit; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(36); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                                }
                            }
                        }
                        Column { width: parent.width; spacing: Style.space(3)
                            Text { text: "Lid action"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                            Dropdown {
                                id: planLidDropdown
                                width: parent.width
                                value: root.lidFor(root.plan)
                                options: Model.lidActions.map(function(a) { return ({ value: a, label: Model.lidActionLabel(a) }) })
                                foreground: root.bar.foreground
                                fontFamily: root.bar.fontFamily
                                onChanged: function(v) { root.setPlanLid(root.plan, v) }
                            }
                        }
                        Column { width: parent.width; spacing: Style.space(3)
                            Text { text: "Auto hibernate after"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                            Row { id: planHibRow; width: parent.width; spacing: Style.space(4)
                                readonly property string state: root.hibFor(root.plan)
                                readonly property bool auto: state === "auto"
                                Button { width: Style.space(40); text: "Auto"; active: planHibRow.auto; tooltipText: planHibRow.auto ? "Auto — use the global hibernate delay for " + root.plan + ". Click for a fixed value." : "Click to use the global hibernate delay for " + root.plan + "."; fontSize: Style.font.caption; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily; horizontalPadding: Style.spacing.controlPaddingX; verticalPadding: Style.spacing.controlPaddingY; bordered: true; anchors.verticalCenter: parent.verticalCenter; onClicked: root.setPlanHib(root.plan, planHibRow.auto ? "60min" : "auto") }
                                PanelSlider { width: parent.width - Style.space(40) - Style.space(56) - Style.space(4) * 2; bar: root.bar; minimum: 15; maximum: 180; step: 15; integer: true; value: root.hibValueMinutes(planHibRow.state); onReleased: function(v) { root.setPlanHib(root.plan, root.hibValueFromSlider(v)) } }
                                Text { text: root.hibValueLabel(planHibRow.state); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; width: Style.space(56); horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                    // SERVICES — the daemons these controls depend on. A stopped
                    // asusd is the usual reason a control in this panel does
                    // nothing, so their state sits with the controls rather than
                    // on Main.
                    Column { visible: root.services.asusd !== undefined; width: parent.width; spacing: Style.space(4)
                        PanelSeparator { foreground: root.bar.foreground }
                        PanelSectionHeader { text: "SERVICES"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
                        Repeater {
                            // One status row per daemon. asusd and supergfxd are
                            // read-only dots; nvidia-powerd is the same now (it is
                            // better left running — it provides Dynamic Boost and
                            // runtime D3). A unit that is genuinely not installed
                            // gets an install button, the one state a button can
                            // fix outright.
                            model: Model.serviceUnits
                            Row {
                                id: svcRow
                                required property var modelData
                                readonly property var state: root.services[svcRow.modelData.id]
                                readonly property bool installable: Model.serviceInstallable(svcRow.modelData, svcRow.state)
                                // nvidia-powerd only appears where the driver is
                                // present or the firmware reports an NVIDIA GPU.
                                visible: !svcRow.modelData.nvidia || root.nvidiaPowerdPresent || root.nvidiaDgpu
                                width: parent.width; spacing: Style.space(6)
                                Rectangle { width: Style.space(8); height: Style.space(8); radius: Style.space(4); anchors.verticalCenter: parent.verticalCenter; color: Model.serviceStateColor(svcRow.state) }
                                Text { text: svcRow.modelData.unit.replace(".service", ""); width: Style.space(90); color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: Model.serviceStateLabel(svcRow.state); color: Model.serviceStateColor(svcRow.state); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                // HoverHandler, not a MouseArea with anchors.fill:
                                // horizontal anchors are not allowed on a Row child
                                // and stop the Row laying out at all.
                                HoverHandler { id: svcHelp }
                                PanelToolTip { visible: svcHelp.hovered; text: svcRow.modelData.tip }
                                Button {
                                    visible: svcRow.installable
                                    text: Model.serviceInstallLabel(svcRow.modelData.id)
                                    tooltipText: "Installs " + svcRow.modelData.pkg + " and enables " + svcRow.modelData.unit + ".\nOpens a terminal so pacman can ask for your password, and\nleaves it open with the result when it is done."
                                    fontSize: Style.font.caption
                                    foreground: root.bar.foreground; fontFamily: root.bar.fontFamily
                                    horizontalPadding: Style.spacing.controlPaddingX
                                    verticalPadding: Style.spacing.controlPaddingY
                                    bordered: true
                                    anchors.verticalCenter: parent.verticalCenter
                                    onClicked: root.installService(svcRow.modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            // The power-plan dropdown owns the keys while its popup is open.
            // Any open dropdown owns the keys while its popup is up.
            blocked: planDropdown.popupOpen || globalLidDropdown.popupOpen || planLidDropdown.popupOpen
            onCloseRequested: root.close()
            onMoveRequested: function(dx, dy) { if (dy !== 0) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - dy * 40)) }
        }
    }

    IpcHandler { target: "io.github.moneytosms.asus"; function open() { root.open() } function close() { root.close() } function show() { root.open() } function hide() { root.close() } function toggle() { root.toggle() } function refresh() { root.refresh() } }
    // Apply the configured per-source mode when the charger is plugged or
    // unplugged (see applyDefaultProfile). This sets only the mode; fps comes
    // from the mode's own default (applyProfileRefresh).
    Connections {
        target: UPower
        function onOnBatteryChanged() { root.applyDefaultProfile() }
    }
    onOpenedChanged: { if (opened) { Qt.callLater(refresh); cursorActive = false } }
    Component.onCompleted: { checkEcoMarker.running = true; checkHyprmoncfg.running = true; oneshotReadProc.running = true }

    // Marker must be read before the first armoury refresh, so it gates checkAsusctl.
    Process { id: checkEcoMarker; command: ["test", "-f", root.ecoMarker]; onExited: function(ec) { root.ecoPending = ec === 0; checkAsusctl.running = true } }
    Process { id: ecoMarkerProc }
    // Writes per-source preset choices back into shell.json's widget settings.
    Process { id: persistProc }
    // Applies the lid action / hibernate delay drop-ins (root write + logind
    // reload); a cancelled pkexec leaves the previous file in place.
    Process {
        id: lidProc
        onExited: function(ec) {
            if (ec === 0) return
            root.showActionError(ec === 126 || ec === 127
                ? "Lid/hibernate: authorisation cancelled — nothing changed. See the README for the polkit rule."
                : "Lid/hibernate: write failed (exit " + ec + ").")
        }
    }
    Process { id: checkAsusctl; command: ["which", "asusctl"]; onExited: function(ec) { root.asusctlAvailable = ec === 0; if (root.asusctlAvailable) refresh() } }
    Process { id: profileProc; command: ["asusctl", "profile", "get"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var p = Model.parseCurrentProfile(text); if (p) { root.currentProfile = p; var i = root.profiles.indexOf(p); if (i >= 0) root.profileIndex = i }; root.acProfile = Model.parseProfiles(text); root.profileLoaded = true } } }
    Process { id: infoProc; command: ["asusctl", "info", "--show-supported"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.supported = Model.parseSupportedFeatures(text); root.initAuraPowerState(root.supported.auraPowerZones || []); root.infoLoaded = true } } }
    Process { id: batteryProc; command: ["asusctl", "battery", "info"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.batteryLimit = Model.parseBatteryInfo(text).limit } } }
    // Persisted one-shot plan, read once at startup so a pending "charge to X"
    // survives a shell restart or reboot.
    Process { id: oneshotReadProc; command: ["cat", root.oneshotStateFile]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.oneshotPlan = Model.oneshotState(text) } } }
    Process { id: oneshotWriteProc }
    Process { id: ledProc; command: ["asusctl", "leds", "get"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.ledBrightness = Model.parseLedBrightness(text) } } }
    Process {
        id: fanDetailProc
        command: ["asusctl", "fan-curve", "--get-enabled"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var info = Model.parseFanCurves(text)
                root.cpuFanEnabled = info.cpuEnabled
                root.gpuFanEnabled = info.gpuEnabled
                root.hasMidFan = info.hasMid
                root.midFanEnabled = info.midEnabled
                root.cpuFanPoints = info.cpuPoints
                root.gpuFanPoints = info.gpuPoints
                root.midFanPoints = info.midPoints
                root.fanCurveEnabled = info.cpuEnabled || info.gpuEnabled || (info.hasMid && info.midEnabled)
                // Also fetch detailed curve data
                if (!fanModProc.running) fanModProc.running = true
            }
        }
    }
    Process {
        id: fanModProc
        command: ["asusctl", "fan-curve", "--mod-profile", root.fanProfile]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var info = Model.parseFanCurves(text)
                if (info.cpuPoints.length > 0) root.cpuFanPoints = info.cpuPoints
                if (info.gpuPoints.length > 0) root.gpuFanPoints = info.gpuPoints
                if (info.midPoints.length > 0) { root.midFanPoints = info.midPoints; root.hasMidFan = true }
            }
        }
    }
    Process { id: armouryProc; command: ["asusctl", "armoury", "list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
        var a = Model.parseArmoury(text)
        root.armourySupported = a.supported
        root.armouryDefaults = a.defaults
        var v = a.values, r = a.ranges
        if (v.panel_overdrive !== undefined) root.panelOverdrive = v.panel_overdrive === 1
        if (v.gpu_mux_mode !== undefined) root.gpuMux = v.gpu_mux_mode === 0
        if (v.dgpu_disable !== undefined) root.dgpuDisable = v.dgpu_disable === 1
        if (v.ppt_pl1_spl !== undefined) root.pptPl1 = v.ppt_pl1_spl
        if (r.ppt_pl1_spl) { root.pptPl1Min = r.ppt_pl1_spl.min; root.pptPl1Max = r.ppt_pl1_spl.max }
        if (v.ppt_pl2_sppt !== undefined) root.pptPl2 = v.ppt_pl2_sppt
        if (r.ppt_pl2_sppt) { root.pptPl2Min = r.ppt_pl2_sppt.min; root.pptPl2Max = r.ppt_pl2_sppt.max }
        if (v.ppt_pl3_fppt !== undefined) root.pptPl3 = v.ppt_pl3_fppt
        if (r.ppt_pl3_fppt) { root.pptPl3Min = r.ppt_pl3_fppt.min; root.pptPl3Max = r.ppt_pl3_fppt.max }
        if (v.nv_dynamic_boost !== undefined) root.nvDynBoost = v.nv_dynamic_boost
        if (r.nv_dynamic_boost) { root.nvDynBoostMin = r.nv_dynamic_boost.min; root.nvDynBoostMax = r.nv_dynamic_boost.max }
        if (v.nv_temp_target !== undefined) root.nvTempTarget = v.nv_temp_target
        if (r.nv_temp_target) { root.nvTempTargetMin = r.nv_temp_target.min; root.nvTempTargetMax = r.nv_temp_target.max }
        if ((a.supported.gpuMux || a.supported.dgpuDisable) && !gpuQueueProc.running) gpuQueueProc.running = true
    } } }
    Process { id: gpuQueueProc; command: Model.gpuQueueCommand(); stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
        var q = Model.parseGpuQueue(text)
        root.queuedDgpu = q.dgpu_disable
        root.queuedMux = q.gpu_mux_mode
        // Rebooted out of Ultimate: finish the pending Eco switch.
        if (root.ecoPending && !root.gpuMux) { root.setEcoPending(false); root.setGpuMode("eco") }
    } } }
    Process { id: monitorProc; command: ["hyprctl", "-j", "monitors"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var m = Model.parseMonitors(text); if (m) root.monitor = m } } }
    Process { id: checkHyprmoncfg; command: ["which", "hyprmoncfg"]; onExited: function(ec) { root.hyprmoncfgAvailable = ec === 0; if (root.hyprmoncfgAvailable && !hyprmoncfgProc.running) hyprmoncfgProc.running = true } }
    // Re-read on every refresh: the active profile changes when monitors are
    // plugged or unplugged, and saving into a stale profile name would either
    // fail or overwrite the wrong one.
    Process { id: hyprmoncfgProc; command: ["hyprmoncfg", "status", "--json"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
        var s = Model.parseHyprmoncfgStatus(text)
        root.hyprmoncfgManaged = s.managed
        root.hyprmoncfgProfile = s.profile
    } } }
    Process {
        id: displayProc
        onExited: function(ec) {
            if (ec === 0 && root.hyprmoncfgManaged && root.hyprmoncfgProfile !== "" && !hyprmoncfgSaveProc.running) {
                hyprmoncfgSaveProc.command = ["hyprmoncfg", "save", root.hyprmoncfgProfile]
                hyprmoncfgSaveProc.running = true
                return
            }
            if (!monitorProc.running) monitorProc.running = true
        }
    }
    Process { id: hyprmoncfgSaveProc; onExited: function() { if (!monitorProc.running) monitorProc.running = true } }
    Process { id: sensorProc; command: Model.sensorCommand(); stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.sensors = Model.parseSensors(text); if (root.oneshotPlan && root.sensors.batPct >= root.oneshotPlan.target) root.stopOneshot() } } }
    // CPU boost switch — sysfs, so it is probed separately from asusctl.
    Process { id: turboProc; command: Model.turboCommand(); stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
        root.turbo = Model.parseTurbo(text)
        root.turboLoaded = true
        // A mode switch that arrived before this first read (bar scroll with the
        // panel closed) is applied now that the kind and polarity are known.
        if (root.pendingBoostMode !== "") { var m = root.pendingBoostMode; root.pendingBoostMode = ""; root.applyProfileBoost(m) }
    } } }
    // Optimistic write: a cancelled pkexec prompt (126/127) or any other failure
    // puts the old value back and says why. On success the next refresh confirms
    // the new one.
    Process {
        id: turboWriteProc
        property bool prevEnabled: false
        onExited: function(ec) {
            if (ec === 0) { if (!turboProc.running) turboProc.running = true; return }
            root.turbo = { kind: root.turbo.kind, enabled: prevEnabled, available: true }
            root.showActionError(ec === 126 || ec === 127
                ? "Turbo Boost: authorisation cancelled (or pkexec missing) — nothing changed. See the README for the polkit rule."
                : "Turbo Boost: write to " + Model.turboPath(root.turbo.kind) + " failed (exit " + ec + ").")
        }
    }
    Process { id: serviceProc; command: Model.serviceStatusCommand(); stdout: StdioCollector { waitForEnd: true; onStreamFinished: { root.services = Model.parseServiceStatus(text) } } }
    Timer { id: errorClearTimer; interval: 8000; onTriggered: root.actionError = "" }
    // Launching the install terminal. A non-zero exit here means the launcher
    // itself failed (no omarchy-launch-tui, no terminal), so the manual command is
    // what the user needs to see.
    Process {
        id: installProc
        property string pkgCommand: ""
        onExited: function(ec) {
            if (ec === 0) return
            root.showActionError("Could not open a terminal for the install — run \"" + installProc.pkgCommand + "\" yourself.")
        }
    }
    Process { id: actionProc; onExited: function() { if (!profileProc.running) profileProc.running = true; if (!batteryProc.running) batteryProc.running = true; if (!ledProc.running) ledProc.running = true; if (!armouryProc.running) armouryProc.running = true; if (!monitorProc.running) monitorProc.running = true; if (!fanDetailProc.running) fanDetailProc.running = true; if (!turboProc.running) turboProc.running = true; if (!serviceProc.running) serviceProc.running = true } }
    Timer { interval: root.refreshInterval; running: root.opened && root.asusctlAvailable; repeat: true; onTriggered: root.refresh() }

    // Sensors run on their own, faster tick — the asusctl round-trip is much
    // heavier and its values barely move. Backs off while the panel is closed,
    // where the readings only feed the bar tooltip.
    Timer {
        interval: root.opened ? 2000 : 20000
        running: root.asusctlAvailable
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!sensorProc.running) sensorProc.running = true
    }
}
