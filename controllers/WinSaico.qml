import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons // qmllint disable import
import "../lib/autosnap.js" as AutoSnap
import "../lib/dispatch.js" as Dispatch
import "../lib/hyprctl.js" as Hyprctl
import "../lib/mode.js" as Mode
import "../lib/monitors.js" as Monitors
import "../lib/style.js" as SystemStyle

// WinSaico: the fourth workspace mode, and auto-fit, its complement. Everything about
// it is here: Super+L walking a workspace through tiling, scrolling, floating and
// WinSaico (lib/mode.js), the Hyprland side that floats the windows (lua/mosaic.lua), the
// default layout, and auto-fit, which deals the windows of a WinSaico workspace into
// the plugin's mosaic (lib/autosnap.js).
//
// WinSaico is a workspace in Omarchy's tiling layout whose windows the plugin floats
// itself, exactly as the picker places a window. It is not Omarchy's floating mode
// (which floats everything that opens, a menu or a popup too, at a set size). The
// workspaces in it are kept in a file next to Omarchy's own layout state, so Omarchy
// never needs to know the mode exists.
Item {
    id: root

    // WinSaico's switch (the `winsaico` option): off, the plugin leaves windows be and
    // the layout keys go back to Omarchy.
    property bool enabled: true
    // The shared options and lists (controllers/Store.qml), and the shell's API.
    property var store: null
    property var shell: null
    property string pluginDir: ""
    // The space between snapped windows, as the host lays them out.
    property int innerGap: 0

    readonly property string pluginId: "io.github.n0rthstar88.snap-layouts"
    readonly property string stateDir: root.store ? root.store.stateDir : ""

    // The plugin's own sentences, in the language Omarchy is set to (i18n/<code>.json).
    Translations {
        id: strings
        directory: Qt.resolvedUrl("../i18n")
    }
    readonly property var texts: ({
        mosaic: strings.t("layout.workspaceMosaic"),
        defaultMosaic: strings.t("layout.defaultMosaic")
    })

    // Has the plugin placed this window? Only then does its closing leave a gap.
    function placed(address) {
        return !!root.fitRecords[address];
    }

    // The default layout of workspaces that have none of their own, as Appearance >
    // Workspace Layout sets it. False for a mode it does not know.
    function setDefault(mode) {
        var command = Dispatch.defaultCommand(mode, root.stateDir, root.texts);
        if (command === "")
            return false;
        Quickshell.execDetached(["sh", "-c", command]);
        root.store.reloadSoon();
        return true;
    }

    // What the keys asked for, until Omarchy has said what the workspace is in.
    property string layoutPending: ""

    // Omarchy's own default-layout file: when anything else rewrites it, a WinSaico
    // default has been replaced, so the mark goes (Dispatch.staleMarkCommand).
    FileView {
        id: omarchyDefaultFile
        path: root.stateDir + "/workspace-layouts/default.lua"
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            Quickshell.execDetached(["sh", "-c", Dispatch.staleMarkCommand(root.stateDir)]);
            root.store.reloadSoon();
        }
    }

    function layoutAction(action) {
        if (!root.enabled)
            return;
        root.layoutPending = action;
        if (!layoutProc.running)
            layoutProc.running = true;
    }

    Process {
        id: layoutProc
        command: ["omarchy-hyprland-workspace-layout-current"]
        stdout: StdioCollector {
            onStreamFinished: root.layoutDone(text.trim())
        }
    }

    function layoutDone(omarchyMode) {
        var workspace = Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : 0;
        if (!(workspace > 0) || root.layoutPending === "")
            return;
        var action = root.layoutPending;
        root.layoutPending = "";
        var current = Mode.current(omarchyMode, root.store.mosaicWorkspaces, workspace, root.store.modeDefaults);
        var target = action === "next" || action === "back" ? Mode.neighbour(current, action) : action;
        var plan = Mode.plan(omarchyMode, target, current);
        var command = plan ? Dispatch.layoutCommand(plan, workspace, root.stateDir, "", root.texts) : "";
        if (command === "")
            return;
        var entering = plan.listed && current !== "mosaic";
        root.store.reloadSoon();
        // Entering: the windows are floated and placed in the same go as the mode
        // changes, so they move once, from where they were to their places (with
        // auto-fit off they keep the place they had). The workspace counts as a mosaic
        // one from now, without waiting for the file.
        if (entering) {
            root.ensureHook();
            if (root.store.mosaicWorkspaces.indexOf(workspace) === -1)
                root.store.mosaicWorkspaces = root.store.mosaicWorkspaces.concat([workspace]);
            root.fitAdopt = root.fitAdopt.concat([workspace]);
            root.fitEntry = { plan: plan, workspace: workspace };
            fitTimer.interval = 1;
            fitTimer.restart();
            return;
        }
        Quickshell.execDetached(["sh", "-c", command]);
    }

    // The Hyprland side (lua/mosaic.lua) floats a window that tiles on a WinSaico workspace
    // as it opens, so the plugin does not have to chase it. A config reload starts the
    // Lua side afresh, so it is loaded at start, after a reload and when the plugin is
    // switched on or off (which it is told, so a plugin that is off leaves windows be).
    readonly property string hookLuaPath: root.pluginDir + "/lua/mosaic.lua"

    onEnabledChanged: root.ensureHook()

    function ensureHook() {
        Quickshell.execDetached(["hyprctl", "eval", "dofile(" + JSON.stringify(root.hookLuaPath) + "); snap_layouts.on = " + (root.enabled ? "true" : "false")]);
    }

    // With WinSaico as the default layout, a tiling workspace joins the plugin's list
    // when it is first seen (shown, or given a window), unless it was set to plain
    // tiling on purpose. One workspace is checked at a time.
    property var listChecks: []

    function mosaicCheck(workspace) {
        var id = Number(workspace);
        if (!root.enabled || !root.store.defaultMosaic || !(id > 0))
            return;
        if (root.store.mosaicWorkspaces.indexOf(id) !== -1 || root.store.plainWorkspaces.indexOf(id) !== -1 || root.listChecks.indexOf(id) !== -1)
            return;
        root.listChecks = root.listChecks.concat([id]);
        if (!listProc.running)
            listProc.startNext();
    }

    Process {
        id: listProc
        property int workspace: 0
        function startNext() {
            if (root.listChecks.length === 0)
                return;
            workspace = root.listChecks[0];
            command = ["omarchy-hyprland-workspace-layout-current", String(workspace)];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var id = listProc.workspace;
                root.listChecks = root.listChecks.slice(1);
                if (text.trim() === "dwindle" && root.store.defaultMosaic && root.store.mosaicWorkspaces.indexOf(id) === -1
                        && root.store.plainWorkspaces.indexOf(id) === -1) {
                    var command = Dispatch.listCommand(id, root.stateDir);
                    if (command !== "") {
                        Quickshell.execDetached(["sh", "-c", command]);
                        root.store.reloadSoon();
                        // It is a mosaic workspace from now; its windows join at once.
                        root.store.mosaicWorkspaces = root.store.mosaicWorkspaces.concat([id]);
                        root.fitAdopt = root.fitAdopt.concat([id]);
                        fitTimer.interval = 60;
                        fitTimer.restart();
                    }
                }
                listProc.startNext();
            }
        }
    }

    // ---------- Auto-fit ----------
    //
    // In WinSaico with auto-fit on, the windows share the screen in the plugin's
    // mosaic (lib/autosnap.js decides): a window that opens takes its place in it and
    // the others make room, and closing one closes the gap. They stay floating, so a
    // window can be resized or moved freely; it goes back to its place at the next
    // fit. With auto-fit off nothing is touched and a new window opens in front and
    // in the middle, as in Omarchy's floating mode.

    // What has joined: { address: { seq } }, and the next number.
    property var fitRecords: ({})
    property int fitSeq: 1
    // Windows that arrived since the last fit, and workspaces whose floating windows
    // all join this time (the mode or auto-fit has just been switched on).
    property var fitFresh: []
    property var fitAdopt: []
    // A mode change waiting to go out together with its placements, and a fit that
    // runs with auto-fit on although the setting has not reached the options yet.
    property var fitEntry: null
    property bool fitForce: false
    // Let a burst of events finish (a window opens, then takes its size): just long
    // enough to catch the next event, short enough that a window is in its place at once.
    readonly property int fitDebounce: 25

    function setAutoFit(on) {
        if (!root.store.save({ autoFit: on }))
            return false;
        if (on) {
            // The setting is on its way to the file; this fit does not wait for it.
            root.fitForce = true;
            root.fitAdopt = root.fitAdopt.concat(root.store.mosaicWorkspaces);
            fitTimer.interval = 1;
            fitTimer.restart();
        }
        return true;
    }

    // A window opened on, or was moved to, a workspace: fit it if it is a mosaic one.
    function fitNotice(hex, workspace) {
        if (!root.enabled || !hex)
            return;
        if (root.store.mosaicWorkspaces.indexOf(parseInt(workspace)) === -1)
            return;
        root.fitFresh = root.fitFresh.concat(["0x" + hex]);
        fitTimer.interval = root.fitDebounce;
        fitTimer.restart();
    }

    function fitSoon() {
        if (root.enabled && root.store.mosaicWorkspaces.length > 0) {
            fitTimer.interval = root.fitDebounce;
            fitTimer.restart();
        }
    }

    Timer {
        id: fitTimer
        onTriggered: {
            if (fitProc.running)
                fitTimer.restart();
            else if (root.store.mosaicWorkspaces.length > 0)
                fitProc.running = true;
        }
    }

    Process {
        id: fitProc
        command: ["sh", "-c", "hyprctl -j monitors; printf '\\n@@SNAP@@\\n'; hyprctl -j clients; printf '\\n@@SNAP@@\\n'; hyprctl -j workspaces; printf '\\n@@SNAP@@\\n'; hyprctl -j plugin list; printf '\\n@@SNAP@@\\n'; hyprctl -j getoption general:gaps_out; printf '\\n@@SNAP@@\\n'; hyprctl -j getoption general:border_size"]
        stdout: StdioCollector {
            onStreamFinished: root.fitDeal(Hyprctl.parseSections(text))
        }
        // Should the gathering fail, the mode change still goes out, without placements.
        onExited: {
            if (root.fitEntry) {
                var entry = root.fitEntry;
                root.fitEntry = null;
                var command = Dispatch.layoutCommand(entry.plan, entry.workspace, root.stateDir, "", root.texts);
                if (command !== "")
                    Quickshell.execDetached(["sh", "-c", command]);
            }
        }
    }

    function fitDeal(s) {
        var monitors = s[0] || [], clients = s[1] || [], workspaces = s[2] || [];
        var style = SystemStyle.resolve(s[4], s[5]);
        var gaps = { outer: style.outer, inner: root.innerGap, border: style.border };
        var fresh = root.fitFresh, adopting = root.fitAdopt;
        var entry = root.fitEntry;
        var fitOn = root.store.options.autoFit || root.fitForce;
        root.fitFresh = [];
        root.fitAdopt = [];
        root.fitEntry = null;
        root.fitForce = false;

        // Forget windows that are gone.
        var alive = {};
        clients.forEach(function(c) { alive[c.address] = true; });
        var records = {};
        Object.keys(root.fitRecords).forEach(function(a) {
            if (alive[a])
                records[a] = root.fitRecords[a];
        });

        // WinSaico windows have no title bar, so a window's own area is the whole zone.
        var lua = [];
        var seq = root.fitSeq;
        root.store.mosaicWorkspaces.forEach(function(id) {
            if (!fitOn) {
                // Auto-fit off: a workspace that has just joined floats its tiled windows
                // where they are; nothing else is touched.
                if (adopting.indexOf(id) !== -1)
                    lua.push(Dispatch.autoPlace(AutoSnap.keep(id, clients)));
                return;
            }
            var info = workspaces.filter(function(w) { return Number(w.id) === id; })[0];
            var monitor = info ? Monitors.byId(monitors, info.monitorID) : null;
            if (!monitor)
                return;
            var result = AutoSnap.plan({ monitor: monitor, gaps: gaps, workspaceId: id, clients: clients,
                records: records, newAddresses: fresh, adopt: adopting.indexOf(id) !== -1, nextSeq: seq });
            seq = result.nextSeq;
            lua.push(Dispatch.autoPlace(result.items));
            result.items.forEach(function(item) {
                records[item.address] = { seq: item.seq };
            });
        });
        root.fitRecords = records;
        root.fitSeq = seq;
        var script = lua.filter(function(l) { return l !== ""; }).join("; ");
        if (entry) {
            // The mode change goes out with the placements right behind it.
            var command = Dispatch.layoutCommand(entry.plan, entry.workspace, root.stateDir, script, root.texts);
            if (command !== "")
                Quickshell.execDetached(["sh", "-c", command]);
        } else if (script !== "") {
            Quickshell.execDetached(["hyprctl", "eval", script]);
        }
    }
}
