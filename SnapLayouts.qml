pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "components"
import "lib/layouts.js" as Layouts
import "lib/edge.js" as Edge
import "lib/monitors.js" as Monitors
import "lib/windows.js" as Windows
import "lib/overview.js" as Overview

// Windows 11-style snap layouts for floating Hyprland windows.
//
// Three ways in:
//   - Super+Z (Hyprland event "io.github.n0rthstar88.snap-layouts:toggle") opens the layout
//     picker for the focused window.
//   - Dragging a window to the top edge of a screen shows the same picker;
//     releasing over a zone snaps the window there. The plugin installs the
//     mouse binds for this itself (hook.lua); see "Drag-to-snap setting".
//   - omarchy-shell snaplayouts toggle
//
// After the first window is placed, "snap assist" offers the other open
// windows for each remaining zone of the chosen layout.
Item {
    id: root

    property var shell: null
    property var manifest: null
    readonly property string pluginId: "io.github.n0rthstar88.snap-layouts"

    // outerGap: space between snapped windows and the screen edge.
    // innerGap: space between snapped windows (0 = flush, borders touching).
    // borderSize must match Hyprland's general.border_size. Hyprland's Lua
    // config doesn't report these through `hyprctl getoption`, so they are set here.
    readonly property int outerGap: 2
    readonly property int innerGap: 0
    readonly property int borderSize: 2
    // titleBarHeight must match hyprbars' bar_height. The bar is drawn above
    // the window's own area, so when hyprbars is loaded windows are placed
    // this much lower to keep the bar inside the zone.
    readonly property int titleBarHeight: 24
    property bool hasTitleBars: false

    // How close (logical px) to the top of a screen the pointer must be while
    // dragging a window before the picker appears.
    readonly property int dragTriggerDistance: 30

    // Layout data and geometry live in lib/layouts.js.
    readonly property var layouts: Layouts.LAYOUTS
    readonly property int pickerCount: Layouts.PICKER_COUNT

    // Settings handed to the pure libraries.
    readonly property var gaps: ({ outer: outerGap, inner: innerGap, border: borderSize })
    readonly property var cardMetrics: ({ padding: cardPadding, gap: thumbGap, thumbHeight: thumbHeight })
    readonly property var edgeOptions: ({ margin: edgeMargin, corner: edgeCorner })
    readonly property var overviewOptions: ({ gapX: 40, gapY: 62, maxHeightFraction: 0.62 })


    // "" hidden, "picker" (Super+Z), "drag" (window held at the top edge),
    // "assist" (choosing windows for the remaining zones).
    property string mode: ""
    readonly property bool opened: mode !== ""

    // Monitor the overlay is on: { name, x, y, w, h, reserved: [l, t, r, b],
    // workspaceId }. Logical pixels, global coordinates.
    property var monitor: null
    property var monitors: []
    property var clients: []
    property string targetAddress: ""

    property int hoverLayout: -1
    property int hoverZone: -1

    // Edge/corner snap: hold a dragged window against a screen edge or corner,
    // wait a moment, and a preview of the landing zone fades in. Releasing
    // snaps the window there; moving away cancels.
    readonly property int edgeMargin: 12
    readonly property int edgeCorner: 90
    readonly property int edgeDwellMs: 320
    property string edgePending: ""
    property double edgePendingAt: 0

    // Snap assist is paged: at most assistPageSize windows per page.
    readonly property int assistPageSize: 6
    property int assistPage: 0
    function assistGo(delta) {
        var pages = Math.max(1, Math.ceil(root.candidates.length / root.assistPageSize));
        root.assistPage = Math.max(0, Math.min(pages - 1, root.assistPage + delta));
    }

    // Window overview (Alt+Tab): every open window, pick one to bring forward.
    property int overviewIndex: 0
    property var overviewRects: []
    // 0 = every window sits where it really is, 1 = settled in the overview.
    property real overviewT: 1
    NumberAnimation {
        id: overviewAnim
        target: root
        property: "overviewT"
        from: 0
        to: 1
        duration: 260
        easing.type: Easing.OutCubic
    }

    // Thumbnails in rows of equal height; the maths is in lib/overview.js.
    function overviewLayout(list, area) {
        var windows = list.map(function(c) {
            return { at: c.at, size: c.size, monitor: root.monitorById(c.monitor) || root.monitor };
        });
        return Overview.layoutRows(windows, area, root.overviewOptions);
    }

    function overviewNeighbor(dir) {
        root.overviewIndex = Overview.neighbor(root.overviewRects, root.overviewIndex, dir);
    }

    function overviewMove(delta) {
        root.overviewIndex = Overview.step(root.overviewIndex, delta, root.candidates.length);
    }

    function toggleOverview() {
        if (root.mode === "overview")
            root.close();
        else if (!root.opened)
            root.requestSnapshot("overview");
    }

    function startOverview() {
        var m = root.activeIpc ? root.monitorById(root.activeIpc.monitor) : null;
        if (!m && root.monitors.length > 0)
            m = root.monitors[0];
        if (!m)
            return;
        var list = Windows.sortForOverview(root.clients.filter(Windows.isSnappable));
        if (list.length === 0)
            return;
        var top = m.reserved[1] + 50;
        root.monitor = m;
        root.targetAddress = "";
        root.placedAddresses = [];
        root.candidates = list;
        root.overviewIndex = Windows.previousWindowIndex(list);
        root.assistPage = 0;
        root.overviewRects = root.overviewLayout(list, { x: 70, y: top, w: m.w - 140, h: m.h - top - 120 });
        root.overviewT = 0;
        root.mode = "overview";
        overviewAnim.restart();
    }


    // Bring a window to the front: restore it if minimized, switch to its
    // workspace, focus it, and raise it above any floating windows on top.
    function focusWindow(address) {
        var c = root.clientByAddress(address);
        var sel = "address:" + address;
        var lua = [];
        // A tiled window can't be raised above floating ones, so the floating
        // windows covering it join the mosaic instead: everything stays tiled,
        // visible side by side, and resizable.
        Windows.floatsCovering(c, root.clients).forEach(function(covering) {
            lua.push("hl.dispatch(hl.dsp.window.float({ action = 'off', window = 'address:" + covering + "' }))");
        });
        if (c && c.workspace && String(c.workspace.name) === Windows.MINIMIZED_WORKSPACE && root.monitor)
            lua.push("hl.dispatch(hl.dsp.window.move({ workspace = '" + root.monitor.workspaceId + "', window = '" + sel + "' }))");
        lua.push("hl.dispatch(hl.dsp.focus({ window = '" + sel + "' }))");
        lua.push("hl.dispatch(hl.dsp.window.bring_to_top())");
        Quickshell.execDetached(["hyprctl", "eval", lua.join("; ")]);
        root.close();
    }

    // The overview panel covers the usable area of the screen, with a margin.

    property int assistLayout: -1
    property var assistZones: []
    property var placedAddresses: []
    readonly property int assistZone: assistZones.length > 0 ? assistZones[0] : -1
    property var candidates: []

    // Drag tracking between the left-button press and release events.
    property bool buttonDown: false
    property var dragStart: null
    property bool dragging: false
    property double pressedAt: 0

    // ---------- Geometry ----------


    function monitorAt(x, y) {
        return Monitors.at(root.monitors, x, y);
    }

    function monitorById(id) {
        return Monitors.byId(root.monitorsIpc, id);
    }
    property var monitorsIpc: []

    // Where a zone lands on screen, in global logical pixels, already inset
    // for gaps and the window border.
    function zoneScreenRect(layoutIndex, zoneIndex) {
        return Layouts.zoneScreenRect(root.monitor, root.gaps, layoutIndex, zoneIndex);
    }

    // The picker card, in coordinates local to the monitor's overlay.
    readonly property int cardPadding: 16
    readonly property int thumbGap: 12
    readonly property int thumbHeight: 76


    function cardRect() {
        return Layouts.cardRect(root.monitor, root.cardMetrics);
    }

    function thumbRect(i) {
        return Layouts.thumbRect(root.monitor, root.cardMetrics, i);
    }

    // A zone inside a layout thumbnail, relative to that thumbnail.
    function zoneThumbRect(layoutIndex, zoneIndex, tw, th) {
        return Layouts.zoneThumbRect(layoutIndex, zoneIndex, tw, th);
    }

    function hitTest(lx, ly) {
        return Layouts.hitTest(root.monitor, root.cardMetrics, lx, ly);
    }

    // ---------- Window helpers ----------

    function clientByAddress(address) {
        for (var i = 0; i < root.clients.length; i++)
            if (root.clients[i].address === address)
                return root.clients[i];
        return null;
    }

    function toplevelFor(address) {
        var all = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        for (var i = 0; i < all.length; i++)
            if ("0x" + String(all[i].address) === address)
                return all[i];
        return null;
    }

    property var iconCache: ({})
    function iconFor(client) {
        var cls = String(client.class || client.initialClass || "").toLowerCase();
        if (Object.prototype.hasOwnProperty.call(root.iconCache, cls))
            return root.iconCache[cls];
        var entries = DesktopEntries.applications ? DesktopEntries.applications.values : [];
        var icon = cls;
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            if (String(e.id || "").toLowerCase().replace(/\.desktop$/, "") === cls
                    || String(e.startupClass || "").toLowerCase() === cls) {
                icon = String(e.icon || cls);
                break;
            }
        }
        var path = Quickshell.iconPath(icon, true) || Quickshell.iconPath("application-x-executable", true);
        root.iconCache[cls] = path;
        return path;
    }


    function refreshCandidates() {
        var offered = root.clients.filter(function(c) {
            return Windows.isSnappable(c) && root.placedAddresses.indexOf(c.address) === -1;
        });
        root.candidates = Windows.sortForAssist(offered, root.monitor ? root.monitor.workspaceId : -1);
    }

    function placeWindow(address, layoutIndex, zoneIndex) {
        var r = root.zoneScreenRect(layoutIndex, zoneIndex);
        var c = root.clientByAddress(address);
        var sel = "address:" + address;
        // Only windows on a floating workspace carry a title bar; on a tiled
        // workspace nothing is drawn above the window, so no offset.
        var hasBar = root.hasTitleBars && c && (c.tags || []).some(function(t) {
            return String(t).replace("*", "") === "omarchy-floating-workspace";
        });
        var bar = hasBar ? root.titleBarHeight : 0;
        var lua = [];
        if (c && c.workspace && Number(c.workspace.id) !== root.monitor.workspaceId)
            lua.push("hl.dispatch(hl.dsp.window.move({ workspace = '" + root.monitor.workspaceId
                + "', follow = false, window = '" + sel + "' }))");
        if (c && c.fullscreen && Number(c.fullscreen) > 0) {
            lua.push("hl.dispatch(hl.dsp.focus({ window = '" + sel + "' }))");
            lua.push("hl.dispatch(hl.dsp.window.fullscreen({ mode = 'fullscreen' }))");
        }
        if (c && c.floating === false)
            lua.push("hl.dispatch(hl.dsp.window.float({ action = 'toggle', window = '" + sel + "' }))");
        lua.push("hl.dispatch(hl.dsp.window.resize({ x = " + r.w + ", y = " + (r.h - bar) + ", window = '" + sel + "' }))");
        lua.push("hl.dispatch(hl.dsp.window.move({ x = " + r.x + ", y = " + (r.y + bar) + ", window = '" + sel + "' }))");
        lua.push("hl.dispatch(hl.dsp.focus({ window = '" + sel + "' }))");
        lua.push("hl.dispatch(hl.dsp.window.bring_to_top())");
        Quickshell.execDetached(["hyprctl", "eval", lua.join("; ")]);
        root.placedAddresses = root.placedAddresses.concat([address]);
    }

    // ---------- Flow ----------

    function toggle() {
        if (root.opened)
            root.close();
        else
            root.requestSnapshot("picker");
    }

    // Shell overlay contract (omarchy-shell shell summon io.github.n0rthstar88.snap-layouts).
    function open(payload) {
        if (!root.opened)
            root.requestSnapshot("picker");
    }

    function close() {
        if (root.mode === "")
            return;
        root.mode = "";
        root.assistPage = 0;
        root.edgePending = "";
        root.hoverLayout = -1;
        root.hoverZone = -1;
        root.assistLayout = -1;
        root.assistZones = [];
        root.placedAddresses = [];
        root.candidates = [];
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide(root.pluginId);
    }

    function startPicker() {
        var active = root.activeIpc;
        if (!active || !active.address || (active.fullscreen && Number(active.fullscreen) > 0))
            return;
        var m = root.monitorById(active.monitor);
        if (!m)
            return;
        root.monitor = m;
        root.targetAddress = active.address;
        root.hoverLayout = -1;
        root.hoverZone = -1;
        root.mode = "picker";
    }

    // The first window is placed: snap it, then offer windows for the rest.
    function chooseZone(layoutIndex, zoneIndex) {
        if (layoutIndex < 0 || zoneIndex < 0 || !root.targetAddress) {
            root.close();
            return;
        }
        root.placedAddresses = [];
        root.placeWindow(root.targetAddress, layoutIndex, zoneIndex);
        var rest = [];
        for (var j = 0; j < root.layouts[layoutIndex].length; j++)
            if (j !== zoneIndex)
                rest.push(j);
        root.assistLayout = layoutIndex;
        root.assistZones = rest;
        root.hoverLayout = -1;
        root.hoverZone = -1;
        root.refreshCandidates();
        if (root.assistZones.length === 0 || root.candidates.length === 0) {
            root.close();
            return;
        }
        root.mode = "assist";
    }

    function assistPick(address) {
        if (root.assistZone < 0)
            return;
        root.placeWindow(address, root.assistLayout, root.assistZone);
        root.assistZones = root.assistZones.slice(1);
        root.refreshCandidates();
        if (root.assistZones.length === 0 || root.candidates.length === 0)
            root.close();
    }

    // Skip the current empty zone in snap assist.
    function assistSkip() {
        root.assistZones = root.assistZones.slice(1);
        if (root.assistZones.length === 0)
            root.close();
    }

    // ---------- Hyprland state ----------

    property string snapshotReason: ""
    property var activeIpc: null

    function requestSnapshot(reason) {
        root.snapshotReason = reason;
        if (!snapshotProc.running)
            snapshotProc.running = true;
    }

    function parseSections(text) {
        var parts = String(text).split("\n@@SNAP@@\n");
        var out = [];
        for (var i = 0; i < parts.length; i++) {
            try {
                out.push(JSON.parse(parts[i]));
            } catch (e) {
                out.push(null);
            }
        }
        return out;
    }

    Process {
        id: snapshotProc
        command: ["sh", "-c", "hyprctl -j monitors; printf '\\n@@SNAP@@\\n'; hyprctl -j clients; printf '\\n@@SNAP@@\\n'; hyprctl -j activewindow; printf '\\n@@SNAP@@\\n'; hyprctl -j plugin list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var s = root.parseSections(text);
                root.monitorsIpc = s[0] || [];
                var mons = [];
                for (var i = 0; i < root.monitorsIpc.length; i++)
                    mons.push(Monitors.fromIpc(root.monitorsIpc[i]));
                root.monitors = mons;
                root.clients = s[1] || [];
                root.activeIpc = s[2] && s[2].address ? s[2] : null;
                root.hasTitleBars = (s[3] || []).some(function(p) {
                    return p.name === "hyprbars";
                });
                if (root.snapshotReason === "picker")
                    root.startPicker();
                else if (root.snapshotReason === "overview")
                    root.startOverview();
                else if (root.snapshotReason === "press" && root.buttonDown) {
                    root.dragStart = Windows.positionsOf(root.clients);
                    dragPoll.start();
                }
            }
        }
    }

    Process {
        id: pollProc
        command: ["sh", "-c", "hyprctl -j clients; printf '\\n@@SNAP@@\\n'; hyprctl -j cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: root.handleDragSample(root.parseSections(text))
        }
    }

    // While a mouse button is held: is a window being moved (title-bar drag,
    // Super+drag, or Window controls' right-drag), and is the pointer at the
    // top of a screen?
    Timer {
        id: dragPoll
        interval: 60
        repeat: true
        onTriggered: {
            var held = Date.now() - root.pressedAt;
            // A plain click never moves the window; stop polling quickly. A
            // missed release event can't leave this running forever either.
            if ((!root.dragging && held > 1500) || held > 60000) {
                stop();
                if (root.mode === "drag" || root.mode === "edge")
                    root.close();
                return;
            }
            if (!pollProc.running)
                pollProc.running = true;
        }
    }

    property string dragAddress: ""


    // Which zone the pointer is asking for, if it is against an edge/corner.
    // Layout 0 = halves, layout 5 = quarters.
    function edgeTarget(m, cur) {
        var t = Edge.edgeTarget(m, cur, root.edgeOptions);
        return t ? { layout: Layouts.INDEX[t.layout], zone: t.zone, key: t.key } : null;
    }

    // Edge snap is a quick fit: place the window and stop, no snap assist.
    function quickSnap(layoutIndex, zoneIndex) {
        if (layoutIndex >= 0 && zoneIndex >= 0 && root.targetAddress)
            root.placeWindow(root.targetAddress, layoutIndex, zoneIndex);
        root.close();
    }

    function handleDragSample(s) {
        if (!root.buttonDown || !root.dragStart)
            return;
        var list = s[0];
        var cur = s[1];
        if (!list || !cur)
            return;
        var win = null;
        for (var i = 0; i < list.length; i++) {
            var c = list[i];
            if (root.dragAddress) {
                if (c.address === root.dragAddress)
                    win = c;
                continue;
            }
            var start = root.dragStart[c.address];
            if (!start || Number(c.fullscreen) > 0)
                continue;
            var moved = Math.abs(c.at[0] - start.at[0]) > 4 || Math.abs(c.at[1] - start.at[1]) > 4;
            var sameSize = c.size[0] === start.size[0] && c.size[1] === start.size[1];
            if (moved && sameSize) {
                win = c;
                break;
            }
        }
        if (!win)
            return;
        root.dragAddress = win.address;
        root.dragging = true;

        var m = root.monitorAt(cur.x, cur.y);
        if (!m)
            return;
        var edge = root.edgeTarget(m, cur);
        if (edge) {
            if (root.mode === "edge") {
                root.hoverLayout = edge.layout;
                root.hoverZone = edge.zone;
                return;
            }
            if (root.edgePending !== edge.key) {
                root.edgePending = edge.key;
                root.edgePendingAt = Date.now();
            } else if (Date.now() - root.edgePendingAt >= root.edgeDwellMs && root.mode !== "picker" && root.mode !== "assist") {
                root.monitor = m;
                root.targetAddress = win.address;
                root.hoverLayout = edge.layout;
                root.hoverZone = edge.zone;
                root.mode = "edge";
                return;
            }
        } else {
            root.edgePending = "";
            if (root.mode === "edge") {
                root.hoverLayout = -1;
                root.hoverZone = -1;
                root.close();
                return;
            }
        }
        var nearTop = cur.y - m.y <= root.dragTriggerDistance;
        if (root.mode === "" && nearTop) {
            root.monitor = m;
            root.targetAddress = win.address;
            root.mode = "drag";
        } else if (root.mode === "drag" && nearTop && m.name !== root.monitor.name) {
            root.monitor = m;
        }
        if (root.mode !== "drag")
            return;

        var lx = cur.x - root.monitor.x;
        var ly = cur.y - root.monitor.y;
        var cr = root.cardRect();
        if (ly > cr.y + cr.h + 120 || m.name !== root.monitor.name) {
            root.mode = "";
            root.hoverLayout = -1;
            root.hoverZone = -1;
            return;
        }
        var hit = root.hitTest(lx, ly);
        root.hoverLayout = hit.layout;
        root.hoverZone = hit.zone;
    }

    function handlePress() {
        if (!root.dragEnabled || root.mode === "picker" || root.mode === "assist")
            return;
        root.buttonDown = true;
        root.dragging = false;
        root.dragStart = null;
        root.dragAddress = "";
        root.pressedAt = Date.now();
        root.requestSnapshot("press");
    }

    function handleRelease() {
        if (!root.buttonDown)
            return;
        root.buttonDown = false;
        dragPoll.stop();
        root.dragging = false;
        root.edgePending = "";
        if (root.mode !== "drag" && root.mode !== "edge")
            return;
        var layoutIndex = root.hoverLayout;
        var zoneIndex = root.hoverZone;
        if (layoutIndex < 0 || zoneIndex < 0) {
            root.close();
            return;
        }
        // Wait for the window list so snap assist can offer the other windows.
        root.pendingDrop = { layout: layoutIndex, zone: zoneIndex };
        dropProc.running = true;
    }

    property var pendingDrop: null
    Process {
        id: dropProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.clients = JSON.parse(text);
                } catch (e) {}
                var drop = root.pendingDrop;
                root.pendingDrop = null;
                if (drop && root.mode === "edge")
                    root.quickSnap(drop.layout, drop.zone);
                else if (drop && root.mode === "drag")
                    root.chooseZone(drop.layout, drop.zone);
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // A config reload drops runtime binds; put drag-to-snap back.
            if (event && event.name === "configreloaded") {
                reloadCheck.restart();
                return;
            }
            if (!event || event.name !== "custom")
                return;
            if (event.data === "io.github.n0rthstar88.snap-layouts:toggle")
                root.toggle();
            else if (event.data === "io.github.n0rthstar88.snap-layouts:overview")
                root.toggleOverview();
            // Title-bar drags (hyprbars) swallow the mouse button, so the
            // press/release binds never fire; hyprbars reports them itself.
            else if (event.data === "io.github.n0rthstar88.snap-layouts:press" || event.data === "hyprbars:dragstart")
                root.handlePress();
            else if (event.data === "io.github.n0rthstar88.snap-layouts:release" || event.data === "hyprbars:dragend")
                root.handleRelease();
        }
    }

    IpcHandler {
        target: "snaplayouts"
        function toggle(): string {
            root.toggle();
            return "ok";
        }
        function close(): string {
            root.close();
            return "ok";
        }
        function overview(): string {
            root.toggleOverview();
            return "ok";
        }
        // Bring a window forward by address, as choosing it in the overview does.
        function focus(address: string): string {
            if (root.clients.length === 0) {
                root.requestSnapshot("none");
                return "no snapshot yet; try again";
            }
            root.focusWindow(address);
            return "ok";
        }
        // Drag-to-snap: `drag on`, `drag off`, or `drag status`.
        function drag(state: string): string {
            if (state === "on" || state === "off")
                root.setDragToSnap(state === "on");
            else if (state !== "status")
                return "expected on, off, or status";
            return root.dragEnabled ? "on" : "off";
        }
        // Pick a zone in the open picker, e.g. `choose 0 0` = left half.
        function choose(layout: int, zone: int): string {
            if (root.mode !== "picker")
                return "picker not open";
            if (layout < 0 || layout >= root.layouts.length || zone < 0 || zone >= root.layouts[layout].length)
                return "no such zone";
            root.chooseZone(layout, zone);
            return "ok";
        }
    }

    // ---------- Drag-to-snap setting ----------

    // Saved in ~/.config/omarchy/shell.json as { "id": "io.github.n0rthstar88.snap-layouts",
    // "dragToSnap": true|false }. Missing means the user hasn't chosen yet:
    // drag-to-snap starts on and a one-time prompt asks whether to keep it.
    readonly property string pluginDir: String((root.manifest && root.manifest.__sourceDir)
        || (Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.pluginId))
    readonly property string hookPath: root.pluginDir + "/hook.lua"
    property bool settingsLoaded: false
    property var settingsEntry: null
    // Set by setDragToSnap() so the choice applies before shell.json is rewritten.
    property var dragOverride: null
    readonly property var dragSetting: root.dragOverride !== null ? root.dragOverride
        : (root.settingsEntry && typeof root.settingsEntry.dragToSnap === "boolean"
            ? root.settingsEntry.dragToSnap : null)
    readonly property bool dragEnabled: root.dragSetting !== false
    readonly property bool askAboutDrag: root.settingsLoaded && root.dragSetting === null
    readonly property string bindDescription: "io.github.n0rthstar88.snap-layouts drag"
    readonly property var dragButtons: ["mouse:272", "mouse:273"]

    onDragEnabledChanged: root.ensureDragBinds()
    onSettingsLoadedChanged: root.ensureDragBinds()

    // Adds the drag binds for any button that lacks them. Binds are only ever
    // added, never removed (see hook.lua for why). When drag-to-snap is off
    // they stay put and handlePress() ignores them.
    function ensureDragBinds() {
        if (!root.settingsLoaded || !root.dragEnabled)
            return;
        if (!bindsProc.running)
            bindsProc.running = true;
    }

    Process {
        id: bindsProc
        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            onStreamFinished: {
                var binds;
                try {
                    binds = JSON.parse(text);
                } catch (e) {
                    console.warn(root.pluginId + ": could not read hyprctl binds: " + e);
                    return;
                }
                var missing = [];
                for (var i = 0; i < root.dragButtons.length; i++) {
                    var press = false;
                    var release = false;
                    for (var j = 0; j < binds.length; j++) {
                        var b = binds[j];
                        if (b.key !== root.dragButtons[i] || b.description !== root.bindDescription)
                            continue;
                        if (b.release)
                            release = true;
                        else
                            press = true;
                    }
                    if (!press || !release)
                        missing.push(root.dragButtons[i]);
                }
                if (missing.length === 0 || !root.dragEnabled)
                    return;
                Quickshell.execDetached(["hyprctl", "eval", "snap_layouts_buttons = "
                    + JSON.stringify(missing).replace("[", "{").replace("]", "}")
                    + "; dofile(" + JSON.stringify(root.hookPath) + ")"]);
            }
        }
    }

    // Other plugins' Keybind:remove() also deletes these binds when they share
    // a button (Window controls does on startup), so check again now and then.
    Timer {
        interval: 30000
        repeat: true
        running: root.settingsLoaded && root.dragEnabled
        onTriggered: root.ensureDragBinds()
    }

    // Lets a config reload finish before checking which binds survived it.
    Timer {
        id: reloadCheck
        interval: 500
        onTriggered: root.ensureDragBinds()
    }

    function setDragToSnap(enabled) {
        root.dragOverride = enabled;
        if (!root.shell || typeof root.shell.updateEntryInline !== "function") {
            console.warn(root.pluginId + ": can't save the drag-to-snap choice; it lasts until the shell restarts");
            return;
        }
        var settings = Object.assign({}, root.settingsEntry || {});
        delete settings.id;
        settings.dragToSnap = enabled;
        root.shell.updateEntryInline(root.pluginId, settings);
    }

    function loadSettings(raw) {
        try {
            var config = JSON.parse(raw);
            var plugins = Array.isArray(config.plugins) ? config.plugins : [];
            var entry = null;
            for (var i = 0; i < plugins.length; i++)
                if (plugins[i] && plugins[i].id === root.pluginId)
                    entry = plugins[i];
            root.settingsEntry = entry;
            if (entry && entry.dragToSnap === root.dragOverride)
                root.dragOverride = null;
        } catch (e) {
            console.warn(root.pluginId + ": could not read shell.json: " + e);
        }
        root.settingsLoaded = true;
    }

    FileView {
        // The shell reads this path directly, not via XDG_CONFIG_HOME.
        path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.loadSettings(text())
        onLoadFailed: root.settingsLoaded = true
        onFileChanged: reload()
    }

    // ---------- UI ----------

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    Loader {
        active: root.opened && root.monitor !== null
        sourceComponent: overlayComponent
    }

    Loader {
        active: root.askAboutDrag
        sourceComponent: askComponent
    }

    Component {
        id: askComponent

        PanelWindow { // qmllint disable uncreatable-type
            screen: {
                var screens = Quickshell.screens;
                var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
                for (var i = 0; i < screens.length; i++)
                    if (screens[i].name === focused)
                        return screens[i];
                return screens.length > 0 ? screens[0] : null;
            }
            anchors.top: true
            margins.top: 12
            implicitWidth: 470
            implicitHeight: askCard.implicitHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "snap-layouts-ask"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                id: askCard
                anchors.fill: parent
                implicitHeight: askColumn.implicitHeight + 32
                radius: Style.cornerRadius + 4
                color: Commons.Color.popups.background
                border.color: Commons.Color.popups.border
                border.width: 1

                Column {
                    id: askColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 10

                    Text {
                        width: parent.width
                        text: "Snap layouts is ready"
                        color: Commons.Color.popups.text
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.heading
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Drag any window to the top of the screen to pick a layout, or press Super+Z. "
                            + "Keep drag-to-snap turned on? You can change this later with "
                            + "\"omarchy-shell snaplayouts drag on/off\"."
                        color: root.withAlpha(Commons.Color.popups.text, 0.8)
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8

                        Repeater {
                            model: [
                                { label: "Turn it off", value: false },
                                { label: "Keep it on", value: true }
                            ]

                            Rectangle {
                                id: askButton
                                required property var modelData
                                width: buttonText.implicitWidth + 28
                                height: 30
                                radius: Style.cornerRadius
                                color: modelData.value
                                    ? (buttonMouse.containsMouse ? Qt.lighter(Commons.Color.accent, 1.15) : Commons.Color.accent)
                                    : (buttonMouse.containsMouse ? root.withAlpha(Commons.Color.popups.text, 0.14) : root.withAlpha(Commons.Color.popups.text, 0.07))
                                border.color: root.withAlpha(Commons.Color.popups.text, 0.2)
                                border.width: modelData.value ? 0 : 1

                                Text {
                                    id: buttonText
                                    anchors.centerIn: parent
                                    text: askButton.modelData.label
                                    color: askButton.modelData.value ? Commons.Color.background : Commons.Color.popups.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }

                                MouseArea {
                                    id: buttonMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setDragToSnap(askButton.modelData.value)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: overlayComponent

        PanelWindow { // qmllint disable uncreatable-type
            id: surface

            screen: {
                var screens = Quickshell.screens;
                for (var i = 0; i < screens.length; i++)
                    if (screens[i].name === root.monitor.name)
                        return screens[i];
                return screens.length > 0 ? screens[0] : null;
            }
            anchors {
                top: true
                right: true
                bottom: true
                left: true
            }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "snap-layouts"
            // The overview sits just under the notifications (Overlay layer), but a
            // fullscreen window hides the Top layer, so there it stays on Overlay.
            WlrLayershell.layer: (root.mode === "overview"
                    && !(root.activeIpc && Number(root.activeIpc.fullscreen) > 0))
                ? WlrLayer.Top : WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.mode === "drag" || root.mode === "edge") ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
            // While a window is being dragged the overlay must not take the pointer.
            mask: (root.mode === "drag" || root.mode === "edge") ? noInput : null

            Region {
                id: noInput
            }

            Item {
                id: content
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()
                Keys.onPressed: function(event) {
                    if (root.mode === "overview") {
                        if (event.key === Qt.Key_Tab) {
                            root.overviewMove(1);
                        } else if (event.key === Qt.Key_Backtab) {
                            root.overviewMove(-1);
                        } else if (event.key === Qt.Key_Right) {
                            root.overviewNeighbor("right");
                        } else if (event.key === Qt.Key_Left) {
                            root.overviewNeighbor("left");
                        }
                        else if (event.key === Qt.Key_Down)
                            root.overviewNeighbor("down");
                        else if (event.key === Qt.Key_Up)
                            root.overviewNeighbor("up");
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            root.focusWindow(root.candidates[root.overviewIndex].address);
                        else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                            var jump = event.key - Qt.Key_1;
                            if (jump < root.candidates.length)
                                root.focusWindow(root.candidates[jump].address);
                        } else
                            return;
                        event.accepted = true;
                    } else if (root.mode === "assist" && event.key === Qt.Key_Tab) {
                        root.assistSkip();
                        event.accepted = true;
                    } else if (root.mode === "assist" && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        var pick = root.assistPage * root.assistPageSize + (event.key - Qt.Key_1);
                        if (pick < root.candidates.length)
                            root.assistPick(root.candidates[pick].address);
                        event.accepted = true;
                    } else if (root.mode === "assist" && (event.key === Qt.Key_Right || event.key === Qt.Key_PageDown)) {
                        root.assistGo(1);
                        event.accepted = true;
                    } else if (root.mode === "assist" && (event.key === Qt.Key_Left || event.key === Qt.Key_PageUp)) {
                        root.assistGo(-1);
                        event.accepted = true;
                    }
                }

                // Click outside the card or the assist panel to cancel.
                MouseArea {
                    anchors.fill: parent
                    enabled: root.mode !== "drag" && root.mode !== "edge"
                    onClicked: root.close()
                }

                // Snap assist dims the screen; filled zones stay outlined.
                Rectangle {
                    anchors.fill: parent
                    visible: root.mode === "assist"
                    color: "black"
                    opacity: 0.35
                }

                // Preview of where the window will land.
                Rectangle {
                    readonly property var r: root.hoverZone >= 0 && root.hoverLayout >= 0
                        ? root.zoneScreenRect(root.hoverLayout, root.hoverZone) : null
                    visible: r !== null && root.mode !== "assist"
                    x: r ? r.x - root.monitor.x : 0
                    y: r ? r.y - root.monitor.y : 0
                    width: r ? r.w : 0
                    height: r ? r.h : 0
                    radius: Style.cornerRadius + 2
                    color: root.withAlpha(Commons.Color.accent, 0.22)
                    border.color: root.withAlpha(Commons.Color.accent, 0.9)
                    border.width: 2
                    opacity: visible ? 1 : 0
                    scale: visible ? 1 : 0.96
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }

                // ----- Window overview -----
                OverviewLayer {
                    anchors.fill: parent
                    visible: root.mode === "overview"
                    rects: root.overviewRects
                    clients: root.candidates
                    selectedIndex: root.overviewIndex
                    progress: root.overviewT
                    topInset: root.monitor ? root.monitor.reserved[1] : 0
                    wallpaper: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
                    toplevelFor: root.toplevelFor
                    iconFor: root.iconFor
                    onSelect: function(index) { root.overviewIndex = index; }
                    onActivated: function(address) { root.focusWindow(address); }
                }

                // ----- Layout picker card -----
                Rectangle {
                    id: card
                    readonly property var r: root.cardRect()
                    visible: root.mode === "picker" || root.mode === "drag"
                    x: r.x
                    y: r.y
                    width: r.w
                    height: r.h
                    radius: Style.cornerRadius + 10
                    color: root.withAlpha(Commons.Color.popups.background, 0.96)
                    border.color: root.withAlpha(Commons.Color.accent, 0.45)
                    border.width: 1
                    opacity: visible ? 1 : 0
                    scale: visible ? 1 : 0.94
                    transformOrigin: Item.Top
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }

                    // Swallow clicks on the card background.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Repeater {
                        model: root.pickerCount

                        Rectangle {
                            id: thumb
                            required property int index
                            readonly property var r: root.thumbRect(index)
                            x: r.x - card.r.x
                            y: r.y - card.r.y
                            width: r.w
                            height: r.h
                            radius: Style.cornerRadius + 2
                            color: root.hoverLayout === index
                                ? root.withAlpha(Commons.Color.accent, 0.14)
                                : root.withAlpha(Commons.Color.popups.text, 0.05)
                            border.color: root.hoverLayout === index
                                ? root.withAlpha(Commons.Color.accent, 0.85)
                                : root.withAlpha(Commons.Color.popups.text, 0.14)
                            border.width: root.hoverLayout === index ? 2 : 1
                            Behavior on color { ColorAnimation { duration: 90 } }
                            Behavior on border.color { ColorAnimation { duration: 90 } }

                            Repeater {
                                model: root.layouts[thumb.index].length

                                Rectangle {
                                    id: zone
                                    required property int index
                                    readonly property var zr: root.zoneThumbRect(thumb.index, index, thumb.width, thumb.height)
                                    readonly property bool hot: root.hoverLayout === thumb.index && root.hoverZone === index
                                    x: zr.x
                                    y: zr.y
                                    width: zr.w
                                    height: zr.h
                                    radius: Math.max(3, Style.cornerRadius / 2 + 1)
                                    color: hot ? Commons.Color.accent : root.withAlpha(Commons.Color.popups.text, 0.28)

                                    Behavior on color {
                                        ColorAnimation { duration: 80 }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -2
                                        enabled: root.mode === "picker"
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: {
                                            root.hoverLayout = thumb.index;
                                            root.hoverZone = zone.index;
                                        }
                                        onExited: {
                                            if (root.hoverLayout === thumb.index && root.hoverZone === zone.index) {
                                                root.hoverLayout = -1;
                                                root.hoverZone = -1;
                                            }
                                        }
                                        onClicked: root.chooseZone(thumb.index, zone.index)
                                    }
                                }
                            }
                        }
                    }
                }

                // ----- Snap assist -----
                Repeater {
                    model: root.mode === "assist" ? root.placedAddresses.length : 0

                    // Outline the zones that are already filled.
                    Rectangle {
                        required property int index
                        readonly property var r: {
                            var all = root.layouts[root.assistLayout];
                            var filled = [];
                            for (var j = 0; j < all.length; j++)
                                if (root.assistZones.indexOf(j) === -1)
                                    filled.push(j);
                            return index < filled.length ? root.zoneScreenRect(root.assistLayout, filled[index]) : null;
                        }
                        visible: r !== null
                        x: r ? r.x - root.monitor.x : 0
                        y: r ? r.y - root.monitor.y : 0
                        width: r ? r.w : 0
                        height: r ? r.h : 0
                        color: "transparent"
                        radius: Style.cornerRadius
                        border.color: root.withAlpha(Commons.Color.popups.text, 0.35)
                        border.width: 1
                    }
                }

                Rectangle {
                    id: assistPanel
                    readonly property var r: root.mode === "assist" && root.assistZone >= 0
                        ? root.zoneScreenRect(root.assistLayout, root.assistZone) : null
                    visible: r !== null
                    x: r ? r.x - root.monitor.x : 0
                    y: r ? r.y - root.monitor.y : 0
                    width: r ? r.w : 0
                    height: r ? r.h : 0
                    radius: Style.cornerRadius + 10
                    color: root.withAlpha(Commons.Color.popups.background, 0.95)
                    border.color: root.withAlpha(Commons.Color.accent, 0.75)
                    border.width: 2

                    MouseArea {
                        anchors.fill: parent
                    }

                    Item {
                        id: assistHeader
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 18
                        height: 30

                        Text {
                            id: assistTitle
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.mode === "overview" ? "Janelas abertas" : "Escolha uma janela para este espaço"
                            color: Commons.Color.popups.text
                            font.family: Qt.application.font.family
                            font.pixelSize: Style.font.body + 3
                            font.weight: Font.DemiBold
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 14
                            visible: assistPanel.width > 560

                            Repeater {
                                model: root.mode === "overview"
                                    ? [
                                        { k: "Tab", t: "próxima" },
                                        { k: "Enter", t: "abrir" },
                                        { k: "Esc", t: "fechar" }
                                    ]
                                    : root.candidates.length > root.assistPageSize
                                    ? [
                                        { k: "1–6", t: "escolher" },
                                        { k: "←  →", t: "página" },
                                        { k: "Tab", t: "pular" },
                                        { k: "Esc", t: "concluir" }
                                    ]
                                    : [
                                        { k: "1–6", t: "escolher" },
                                        { k: "Tab", t: "pular" },
                                        { k: "Esc", t: "concluir" }
                                    ]

                                Row {
                                    id: hint
                                    required property var modelData
                                    spacing: 6

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 22
                                        width: keyLabel.implicitWidth + 14
                                        radius: 6
                                        color: root.withAlpha(Commons.Color.popups.text, 0.1)
                                        border.color: root.withAlpha(Commons.Color.popups.text, 0.18)
                                        border.width: 1

                                        Text {
                                            id: keyLabel
                                            anchors.centerIn: parent
                                            text: hint.modelData.k
                                            color: Commons.Color.popups.text
                                            font.family: Qt.application.font.family
                                            font.pixelSize: Style.font.body - 1
                                            font.weight: Font.Medium
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: hint.modelData.t
                                        color: root.withAlpha(Commons.Color.popups.text, 0.65)
                                        font.family: Qt.application.font.family
                                        font.pixelSize: Style.font.body - 1
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        id: gridArea
                        anchors.top: assistHeader.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 18
                        anchors.topMargin: 14

                        readonly property int total: root.candidates.length
                        readonly property int pages: Math.max(1, Math.ceil(total / root.assistPageSize))
                        readonly property int page: Math.min(root.assistPage, pages - 1)
                        readonly property var pageItems: root.candidates.slice(page * root.assistPageSize, (page + 1) * root.assistPageSize)
                        readonly property real areaW: width
                        readonly property real areaH: height - (pages > 1 ? 36 : 0)
                        readonly property int n: pageItems.length
                        // 1 -> 1 column; 2, 3, 4 -> 2 columns (2 side by side, 2+1, 2x2);
                        // 5, 6 -> 3 columns. Very wide zones get everything in one row.
                        readonly property int cols: {
                            if (n <= 1)
                                return 1;
                            if (areaW / Math.max(1, areaH) > 2.2)
                                return Math.min(n, 4);
                            return n <= 4 ? 2 : 3;
                        }
                        readonly property int rows: Math.max(1, Math.ceil(n / cols))
                        readonly property real cellW: Math.min(areaW / cols, 380)
                        readonly property real cellH: Math.min(areaH / rows, 300)
                        property int hoveredIndex: -1

                        WheelHandler {
                            onWheel: function(event) {
                                root.assistGo(event.angleDelta.y < 0 ? 1 : -1);
                            }
                        }

                        Repeater {
                            model: gridArea.pageItems

                            delegate: Item {
                                id: cell
                                required property var modelData
                                required property int index
                                readonly property int row: Math.floor(index / gridArea.cols)
                                readonly property int inRow: row === gridArea.rows - 1
                                    ? gridArea.n - row * gridArea.cols : gridArea.cols
                                readonly property int globalIndex: root.assistPage * root.assistPageSize + index
                                // One card is selected at a time in the overview; the mouse
                                // moves the selection, so keyboard and mouse never disagree.
                                readonly property bool hovered: root.mode === "overview"
                                    ? globalIndex === root.overviewIndex : tileMouse.containsMouse
                                x: (gridArea.areaW - inRow * gridArea.cellW) / 2 + (index % gridArea.cols) * gridArea.cellW
                                y: (gridArea.areaH - gridArea.rows * gridArea.cellH) / 2 + row * gridArea.cellH
                                width: gridArea.cellW
                                height: gridArea.cellH
                                opacity: gridArea.hoveredIndex < 0 || hovered ? 1 : 0.7
                                Behavior on opacity { NumberAnimation { duration: 140 } }
                                onHoveredChanged: {
                                    if (hovered)
                                        gridArea.hoveredIndex = index;
                                    else if (gridArea.hoveredIndex === index)
                                        gridArea.hoveredIndex = -1;
                                }
                                Connections {
                                    target: tileMouse
                                    function onContainsMouseChanged() {
                                        if (tileMouse.containsMouse && root.mode === "overview")
                                            root.overviewIndex = cell.globalIndex;
                                    }
                                }

                                Item {
                                    id: holder
                                    anchors.fill: parent
                                    anchors.margins: 14
                                    anchors.bottomMargin: 40

                                    Item {
                                        id: thumb
                                        readonly property real aspect: cell.modelData.size && cell.modelData.size[1] > 0
                                            ? cell.modelData.size[0] / cell.modelData.size[1] : 1.6
                                        width: Math.min(holder.width, holder.height * aspect)
                                        height: width / aspect
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: cell.hovered ? -5 : 0
                                        scale: cell.hovered ? 1.06 : 1
                                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                        // Soft shadow, and an accent glow while hovered.
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: -3
                                            anchors.topMargin: 4
                                            anchors.bottomMargin: -8
                                            radius: 16
                                            color: "black"
                                            opacity: 0.28
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: -10
                                            radius: 22
                                            color: Commons.Color.accent
                                            opacity: cell.hovered ? 0.4 : 0
                                            Behavior on opacity { NumberAnimation { duration: 140 } }
                                        }

                                        // Window picture, clipped to rounded corners.
                                        Item {
                                            id: shot
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.smooth: true
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: shotMask
                                                maskThresholdMin: 0.3
                                                maskSpreadAtMin: 0.3
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                color: root.withAlpha(Commons.Color.background, 0.7)
                                            }

                                            ScreencopyView {
                                                id: preview
                                                readonly property var source: root.toplevelFor(cell.modelData.address)
                                                anchors.fill: parent
                                                captureSource: source && source.wayland ? source.wayland : null
                                                live: false
                                                paintCursor: false
                                            }
                                        }

                                        Rectangle {
                                            id: shotMask
                                            anchors.fill: parent
                                            visible: false
                                            layer.enabled: true
                                            radius: 12
                                            color: "black"
                                        }

                                        // Hover ring, drawn above the picture.
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 12
                                            color: "transparent"
                                            border.color: Commons.Color.accent
                                            border.width: 3
                                            opacity: cell.hovered ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                        }

                                        // Windows with no capture (e.g. minimized) show a big icon.
                                        Image {
                                            anchors.centerIn: parent
                                            visible: !preview.hasContent
                                            width: Math.min(64, parent.height * 0.5)
                                            height: width
                                            source: root.iconFor(cell.modelData)
                                            sourceSize.width: 128
                                            sourceSize.height: 128
                                        }

                                        // App icon on the bottom edge.
                                        Image {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            y: parent.height - height * 0.5
                                            width: 46
                                            height: 46
                                            source: root.iconFor(cell.modelData)
                                            sourceSize.width: 92
                                            sourceSize.height: 92
                                        }

                                        // Which workspace the window lives on (overview only).
                                        Rectangle {
                                            visible: root.mode === "overview"
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 8
                                            height: 20
                                            width: wsLabel.implicitWidth + 14
                                            radius: 10
                                            color: root.withAlpha(Commons.Color.background, 0.78)
                                            Text {
                                                id: wsLabel
                                                anchors.centerIn: parent
                                                text: String(cell.modelData.workspace && cell.modelData.workspace.name === "special:minimized"
                                                    ? "Minimizada" : "Área " + (cell.modelData.workspace ? cell.modelData.workspace.id : ""))
                                                color: Commons.Color.popups.text
                                                font.family: Qt.application.font.family
                                                font.pixelSize: Style.font.body - 2
                                            }
                                        }

                                        // Shortcut number, per page.
                                        Rectangle {
                                            x: 8
                                            y: 8
                                            width: 20
                                            height: 20
                                            radius: 10
                                            color: root.withAlpha(Commons.Color.background, 0.78)
                                            Text {
                                                anchors.centerIn: parent
                                                text: String(cell.index + 1)
                                                color: Commons.Color.popups.text
                                                font.family: Qt.application.font.family
                                                font.pixelSize: Style.font.body - 2
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }

                                // Window title, shown on hover.
                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    horizontalAlignment: Text.AlignHCenter
                                    text: String(cell.modelData.title || cell.modelData.class || "Janela")
                                    color: Commons.Color.popups.text
                                    font.family: Qt.application.font.family
                                    font.pixelSize: Style.font.body
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    opacity: cell.hovered ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }

                                MouseArea {
                                    id: tileMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.mode === "overview" ? root.focusWindow(cell.modelData.address) : root.assistPick(cell.modelData.address)
                                }
                            }
                        }

                        // Page controls.
                        Row {
                            visible: gridArea.pages > 1
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12
                            height: 26

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "‹"
                                font.pixelSize: 22
                                color: root.withAlpha(Commons.Color.popups.text, gridArea.page > 0 ? 0.9 : 0.3)
                                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.assistGo(-1) }
                            }

                            Repeater {
                                model: gridArea.pages

                                Rectangle {
                                    required property int index
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: index === gridArea.page ? 20 : 8
                                    height: 8
                                    radius: 4
                                    color: index === gridArea.page
                                        ? Commons.Color.accent
                                        : root.withAlpha(Commons.Color.popups.text, 0.35)
                                    Behavior on width { NumberAnimation { duration: 120 } }
                                    MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: root.assistPage = parent.index }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "›"
                                font.pixelSize: 22
                                color: root.withAlpha(Commons.Color.popups.text, gridArea.page < gridArea.pages - 1 ? 0.9 : 0.3)
                                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.assistGo(1) }
                            }
                        }
                    }
                }
            }
        }
    }
}
