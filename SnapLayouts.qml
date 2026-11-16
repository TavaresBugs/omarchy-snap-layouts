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
import "lib/navigation.js" as Navigation
import "lib/dispatch.js" as Dispatch
import "lib/windows.js" as Windows
import "lib/overview.js" as Overview
import "lib/settings.js" as Settings
import "lib/style.js" as SystemStyle
import "lib/workspaces.js" as Workspaces

// Windows 11-style snap layouts for Hyprland windows, plus an Alt+Tab style overview.
//
// Ways in:
//   - Super+Z (Hyprland event "io.github.n0rthstar88.snap-layouts:toggle") opens the layout
//     picker for the focused window.
//   - Dragging a window to the top edge of a screen shows the same picker;
//     releasing over a zone snaps the window there. The plugin installs the
//     mouse binds for this itself (hook.lua); see "Drag-to-snap setting".
//   - Dragging against a side edge or a corner (or the very top) shows a preview
//     of a half, a quarter or the whole usable area; releasing snaps there.
//   - "...:overview" (for example on Alt+Tab) opens the window overview.
//   - omarchy-shell snaplayouts toggle | overview
//
// After the first window is placed, "snap assist" offers the other open
// windows for each remaining zone of the chosen layout.
//
// Structure: decisions live in lib/ (pure JS, unit tested), views in components/,
// and this file keeps the state machine and the Hyprland I/O. See
// docs/ARCHITECTURE.md.
Item {
    id: root

    property var shell: null
    property var manifest: null
    readonly property string pluginId: "io.github.n0rthstar88.snap-layouts"

    // If the shell restarted while the overview's submap was active, shortcuts
    // would stay paused; give them back.
    Component.onCompleted: Quickshell.execDetached(["hyprctl", "eval", Dispatch.LEAVE_OVERVIEW_MODE])

    // The system's look, read from Hyprland with every snapshot (lib/style.js):
    // gap to the screen edge and border width.
    property var style: SystemStyle.resolve(null, null)
    // innerGap: space between snapped windows (0 = flush, borders touching).
    readonly property int innerGap: 0
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
    readonly property var gaps: ({ outer: style.outer, inner: innerGap, border: style.border })
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
    readonly property int edgeMargin: root.options.edgeMargin
    readonly property int edgeCorner: root.options.edgeCorner
    readonly property int edgeDwellMs: root.options.edgeDwellMs
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
    // The workspace whose windows the overview shows, and the strip of all of them.
    property int overviewWorkspace: 0
    property var workspaceScreens: []
    // The keyboard is on the workspace strip rather than on the windows.
    property bool stripFocus: false
    // The overview is playing its closing animation.
    property bool closing: false
    // The system's shortcuts are paused while the overview is open (see
    // overview-mode.lua); this remembers that we asked, and when.
    property bool modal: false
    property double modalSince: 0
    // A window to select again after the next refresh (it moved).
    property string pendingSelect: ""
    // The overview shows the workspace the monitor is showing, so its windows
    // can travel to and from their real places; otherwise they fade.
    readonly property bool overviewMorph: root.monitor ? root.overviewWorkspace === root.monitor.workspaceId : true
    // Workspace events caused by the plugin itself (moving, swapping) are not a
    // reason to change what the overview shows.
    property double ignoreWorkspaceUntil: 0
    property int followTarget: 0
    property int overviewSwitchTick: 0
    property int overviewSwitchDir: 0
    // 0 = every window sits where it really is, 1 = settled in the overview.
    property real overviewT: 1
    NumberAnimation {
        id: overviewAnim
        target: root
        property: "overviewT"
        from: 0
        to: 1
        duration: 360
        // Fast out of the blocks, long soft landing.
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
    }
    // Closing runs the opening backwards: the windows travel back to their
    // places, and only then does the overview go away.
    NumberAnimation {
        id: closeAnim
        target: root
        property: "overviewT"
        to: 0
        duration: 260
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.65, 0, 0.35, 1, 1, 1]
        onFinished: root.hide()
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
        if (!m || root.clients.filter(Windows.isSnappable).length === 0)
            return;
        root.monitor = m;
        root.targetAddress = "";
        root.placedAddresses = [];
        root.assistPage = 0;
        root.closing = false;
        root.stripFocus = false;
        root.overviewWorkspace = m.workspaceId;
        root.refreshOverview(true);
        root.mode = "overview";
        root.enterModal();
    }

    // The snapshot changed what a monitor shows: take the monitor again, then lay out.
    function refreshAfterChange(slide) {
        var fresh = root.monitor ? root.monitorById(root.monitor.id) : null;
        if (fresh)
            root.monitor = fresh;
        root.refreshOverview(false, slide);
    }

    // The strips, rebuilt from the latest snapshot.
    function refreshStrips() {
        var offered = root.clients.filter(Windows.isSnappable);
        var byId = Monitors.indexById(root.monitorsIpc);
        root.workspaceScreens = root.options.overviewScope === "all" ? []
            : Workspaces.screens(offered, byId, root.overviewWorkspace, root.mainMonitor, root.style.outer);
    }

    // Lay out the windows of overviewWorkspace (or all of them). `first` also
    // picks the previously used window. Opening animates every window from where
    // it really is; `slide` (-1, 0 or 1) instead slides the new set in from that
    // side, which is how a change of workspace looks.
    function refreshOverview(first, slide) {
        var m = root.monitor;
        var offered = root.clients.filter(Windows.isSnappable);
        var scoped = root.options.overviewScope === "all" ? offered : offered.filter(function(c) {
            return Windows.belongsToWorkspace(c, root.overviewWorkspace);
        });
        var list = Windows.sortForOverview(scoped);
        root.refreshStrips();
        root.candidates = list;
        root.overviewIndex = first ? Windows.previousWindowIndex(list) : 0;
        if (root.pendingSelect !== "") {
            for (var i = 0; i < list.length; i++)
                if (list[i].address === root.pendingSelect)
                    root.overviewIndex = i;
            root.pendingSelect = "";
        }
        var top = m.reserved[1] + (root.workspaceScreens.length > 0 ? 138 : 50);
        root.overviewRects = root.overviewLayout(list, { x: 70, y: top, w: m.w - 140, h: m.h - top - 70 });
        if (slide === undefined) {
            root.overviewT = 0;
            overviewAnim.restart();
        } else {
            overviewAnim.stop();
            root.overviewT = 1;
            root.overviewSwitchDir = slide;
            root.overviewSwitchTick++;
        }
    }

    function switchOverviewWorkspace(id) {
        if (id === root.overviewWorkspace)
            return;
        var dir = Workspaces.direction(root.workspaceScreens, root.overviewWorkspace, id);
        root.overviewWorkspace = id;
        root.refreshOverview(false, dir);
    }

    function stepOverviewWorkspace(delta) {
        root.switchOverviewWorkspace(Workspaces.stepWorkspace(Workspaces.flatten(root.workspaceScreens), root.overviewWorkspace, delta));
    }

    // A click on a strip thumbnail: look at that workspace's windows.
    function chooseWorkspaceEntry(entry) {
        root.switchOverviewWorkspace(entry.id);
    }

    // ---- Modal overview ----

    // Pause the system's shortcuts while the overview is open, so a key meant for
    // it can't also act on the windows behind it.
    function enterModal() {
        root.modal = true;
        root.modalSince = Date.now();
        Quickshell.execDetached(["hyprctl", "eval", "dofile(" + JSON.stringify(root.pluginDir + "/overview-mode.lua") + ")"]);
    }

    function leaveModal() {
        if (!root.modal)
            return;
        root.modal = false;
        Quickshell.execDetached(["hyprctl", "eval", Dispatch.LEAVE_OVERVIEW_MODE]);
    }

    // Super+Shift+arrow in the overview: swap, as the same keys do on the desktop.
    // On the strip that is a workspace (left/right); on the windows, the selected
    // window and its neighbour in the real layout.
    function overviewSwap(direction) {
        if (root.mode !== "overview" || root.closing)
            return;
        if (root.stripFocus || root.candidates.length === 0) {
            if (direction === "left" || direction === "right")
                root.swapOverviewWorkspace(direction === "right" ? 1 : -1);
            return;
        }
        var real = root.overviewRects.map(function(r) { return { x: r.rx, y: r.ry, w: r.rw, h: r.rh }; });
        var to = Overview.neighbor(real, root.overviewIndex, direction);
        if (to === root.overviewIndex)
            return;
        var a = root.candidates[root.overviewIndex];
        var b = root.candidates[to];
        if (a.floating || b.floating)
            return;
        var lua = Dispatch.swapWindows(a.address, b.address);
        if (lua === "")
            return;
        root.pendingSelect = a.address;
        Quickshell.execDetached(["hyprctl", "eval", lua]);
        refreshTimer.restart();
    }

    // ---- Following and changing workspaces ----

    // Super+1..5 (or any other workspace change) while the overview is open:
    // look at the workspace the system moved to, so the two never disagree.
    function followWorkspace(id) {
        if (!(id > 0) || id === root.overviewWorkspace)
            return;
        root.followTarget = id;
        root.requestSnapshot("overview-follow");
    }

    // The workspace strip's own numbers can be changed from here too.
    function swapWorkspaces(a, b) {
        if (Workspaces.blockOf(a) !== Workspaces.blockOf(b))
            return;
        var lua = Dispatch.swapWorkspaces(a, b);
        if (lua === "")
            return;
        root.ignoreWorkspaceUntil = Date.now() + 900;
        Quickshell.execDetached(["hyprctl", "eval", lua]);
        // The overview keeps looking at the same windows, which now sit under the other number.
        if (root.overviewWorkspace === a)
            root.overviewWorkspace = b;
        else if (root.overviewWorkspace === b)
            root.overviewWorkspace = a;
        refreshTimer.restart();
    }

    function swapOverviewWorkspace(delta) {
        var to = Workspaces.neighborIn(Workspaces.entriesFor(root.workspaceScreens, root.overviewWorkspace), root.overviewWorkspace, delta);
        if (to > 0)
            root.swapWorkspaces(root.overviewWorkspace, to);
    }

    // Leave the overview and go to a workspace, on the monitor that owns it.
    function goToWorkspace(id) {
        if (root.closing)
            return;
        var owner = Workspaces.monitorFor(id, Monitors.indexById(root.monitorsIpc));
        var lua = Dispatch.goToWorkspace(id, Workspaces.slotOf(id), owner ? owner.name : "");
        if (lua !== "")
            Quickshell.execDetached(["hyprctl", "eval", lua]);
        root.close();
    }

    // A key in the overview. What each key means is decided in lib/navigation.js.
    function overviewKey(event) {
        var names = {};
        names[Qt.Key_Up] = "up";
        names[Qt.Key_Down] = "down";
        names[Qt.Key_Left] = "left";
        names[Qt.Key_Right] = "right";
        names[Qt.Key_Tab] = "tab";
        names[Qt.Key_Backtab] = "backtab";
        names[Qt.Key_PageUp] = "pageup";
        names[Qt.Key_PageDown] = "pagedown";
        names[Qt.Key_Return] = "enter";
        names[Qt.Key_Enter] = "enter";
        var key = names[event.key];
        if (key === undefined) {
            // 1-9 pick a window by its place in the list.
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && !root.stripFocus) {
                var jump = event.key - Qt.Key_1;
                if (jump < root.candidates.length)
                    root.focusWindow(root.candidates[jump].address);
                return true;
            }
            return false;
        }
        var result = Navigation.overviewKey({
            strip: root.stripFocus,
            hasStrip: root.workspaceScreens.length > 0,
            index: root.overviewIndex,
            rects: root.overviewRects,
            count: root.candidates.length
        }, {
            key: key,
            ctrl: !!(event.modifiers & Qt.ControlModifier),
            shift: !!(event.modifiers & Qt.ShiftModifier)
        });
        switch (result.action) {
        case "select": root.overviewIndex = result.index; break;
        case "enterStrip": root.stripFocus = true; break;
        case "leaveStrip": root.stripFocus = false; break;
        case "stepWorkspace": root.stepOverviewWorkspace(result.delta); break;
        case "swapWorkspace": root.swapOverviewWorkspace(result.delta); break;
        case "activate": root.focusWindow(root.candidates[root.overviewIndex].address); break;
        case "activateWorkspace": root.goToWorkspace(root.overviewWorkspace); break;
        }
        return true;
    }

    // What dropping a window onto a workspace would look like, for the strips.
    function previewDrop(workspaceId, address) {
        var c = root.clientByAddress(address);
        for (var i = 0; c && i < root.workspaceScreens.length; i++) {
            var screen = root.workspaceScreens[i];
            for (var j = 0; j < screen.entries.length; j++)
                if (screen.entries[j].id === workspaceId)
                    return Workspaces.dropPreview(screen.entries[j], c, screen.aspect);
        }
        return null;
    }

    // A card dropped on a workspace: send the window there (tiled, if it is
    // joining a tiled layout), stay in the overview and show the result once
    // Hyprland has moved it.
    function moveWindowToWorkspace(address, workspaceId) {
        var owner = Workspaces.monitorFor(workspaceId, Monitors.indexById(root.monitorsIpc));
        var preview = root.previewDrop(workspaceId, address);
        var lua = Dispatch.moveToWorkspace(address, workspaceId, owner ? owner.name : "", preview ? preview.tile : false);
        if (lua === "")
            return;
        root.ignoreWorkspaceUntil = Date.now() + 900;
        Quickshell.execDetached(["hyprctl", "eval", lua]);
        refreshTimer.restart();
    }

    Timer {
        id: refreshTimer
        interval: 250
        onTriggered: root.requestSnapshot("overview-refresh")
    }


    // Bring a window to the front: restore it if minimized, switch to its
    // workspace, focus it, and raise it above any floating windows on top.
    function focusWindow(address) {
        if (root.closing)
            return;
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

    // A rect in global coordinates, relative to the overlay (the current monitor).
    function localRect(r) {
        return { x: r.x - root.monitor.x, y: r.y - root.monitor.y, w: r.w, h: r.h };
    }

    // The zone to tint while hovering a layout, or null.
    function previewZone() {
        if (root.mode === "assist" || root.hoverZone < 0 || root.hoverLayout < 0 || !root.monitor)
            return null;
        return root.localRect(root.zoneScreenRect(root.hoverLayout, root.hoverZone));
    }

    // Outlines of the zones of the chosen layout that already hold a window.
    function filledZones() {
        if (root.mode !== "assist" || !root.monitor || root.assistLayout < 0)
            return [];
        var out = [];
        for (var j = 0; j < root.layouts[root.assistLayout].length; j++)
            if (root.assistZones.indexOf(j) === -1)
                out.push(root.localRect(root.zoneScreenRect(root.assistLayout, j)));
        return out;
    }

    // ---- Snap assist: the window offers, paged, and their layout in the panel ----

    function assistZoneRect() {
        if (root.mode !== "assist" || root.assistZone < 0 || !root.monitor)
            return null;
        return root.localRect(root.zoneScreenRect(root.assistLayout, root.assistZone));
    }

    function assistPageCount() {
        return Math.max(1, Math.ceil(root.candidates.length / root.assistPageSize));
    }

    function assistPageIndex() {
        return Math.min(root.assistPage, root.assistPageCount() - 1);
    }

    function assistPageItems() {
        var start = root.assistPageIndex() * root.assistPageSize;
        return root.candidates.slice(start, start + root.assistPageSize);
    }

    // The thumbnails use the same row layout as the overview, inside the panel.
    function assistCardRects() {
        var zone = root.assistZoneRect();
        if (!zone)
            return [];
        var windows = root.assistPageItems().map(function(c) {
            return { at: c.at, size: c.size, monitor: root.monitorById(c.monitor) || root.monitor };
        });
        var bottom = root.assistPageCount() > 1 ? 56 : 28;
        var area = { x: 24, y: 70, w: zone.w - 48, h: zone.h - 70 - bottom };
        return Overview.layoutRows(windows, area, { gapX: 28, gapY: 56, maxHeightFraction: 0.7 });
    }

    function thumbRects() {
        var out = [];
        for (var i = 0; i < root.pickerCount; i++)
            out.push(root.thumbRect(i));
        return out;
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
        if (!client)
            return "";
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
        root.candidates = Windows.forAssist(offered, root.monitor ? root.monitor.workspaceId : -1);
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
        if (root.mode === "overview") {
            if (root.closing)
                return;
            root.closing = true;
            overviewAnim.stop();
            closeAnim.restart();
            return;
        }
        root.hide();
    }

    function hide() {
        closeAnim.stop();
        root.closing = false;
        root.stripFocus = false;
        root.leaveModal();
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
        command: ["sh", "-c", "hyprctl -j monitors; printf '\\n@@SNAP@@\\n'; hyprctl -j clients; printf '\\n@@SNAP@@\\n'; hyprctl -j activewindow; printf '\\n@@SNAP@@\\n'; hyprctl -j plugin list; printf '\\n@@SNAP@@\\n'; hyprctl -j getoption general:gaps_out; printf '\\n@@SNAP@@\\n'; hyprctl -j getoption general:border_size"]
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
                root.style = SystemStyle.resolve(s[4], s[5]);
                if (root.snapshotReason === "picker")
                    root.startPicker();
                else if (root.snapshotReason === "overview")
                    root.startOverview();
                else if (root.snapshotReason === "overview-refresh" && root.mode === "overview")
                    root.refreshAfterChange(0);
                else if (root.snapshotReason === "overview-follow" && root.mode === "overview" && !root.closing) {
                    var dir = Workspaces.direction(root.workspaceScreens, root.overviewWorkspace, root.followTarget);
                    root.overviewWorkspace = root.followTarget;
                    root.refreshAfterChange(dir);
                }
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
        if (!root.options.edgeSnap)
            return null;
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
            // The submap was left from outside (Escape resets it): leave the overview too.
            if (event && event.name === "submap") {
                if (root.modal && root.mode === "overview" && !root.closing
                        && event.data === "" && Date.now() - root.modalSince > 400) {
                    root.modal = false;
                    root.close();
                }
                return;
            }
            if (event && event.name === "workspacev2") {
                if (root.mode === "overview" && !root.closing && Date.now() > root.ignoreWorkspaceUntil)
                    root.followWorkspace(parseInt(event.data));
                return;
            }
            if (!event || event.name !== "custom")
                return;
            if (event.data === "io.github.n0rthstar88.snap-layouts:toggle")
                root.toggle();
            else if (event.data === "io.github.n0rthstar88.snap-layouts:overview")
                root.toggleOverview();
            else if (event.data.indexOf("io.github.n0rthstar88.snap-layouts:swap-") === 0)
                root.overviewSwap(event.data.substring("io.github.n0rthstar88.snap-layouts:swap-".length));
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
    // Validated user options from shell.json (see lib/settings.js).
    readonly property var options: Settings.resolve(root.settingsEntry)
    // The main screen of the overview strip: a choice made in the overview applies
    // at once, before shell.json has been rewritten.
    property string mainOverride: ""
    readonly property string mainMonitor: root.mainOverride !== "" ? root.mainOverride : root.options.mainMonitor
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

    function setMainMonitor(name) {
        root.mainOverride = name;
        root.refreshStrips();
        if (!root.shell || typeof root.shell.updateEntryInline !== "function") {
            console.warn(root.pluginId + ": can't save the main monitor; it lasts until the shell restarts");
            return;
        }
        var settings = Object.assign({}, root.settingsEntry || {});
        delete settings.id;
        settings.mainMonitor = name;
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
            if (entry && entry.mainMonitor === root.mainOverride)
                root.mainOverride = "";
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
                        if (!root.closing && root.overviewKey(event))
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

                // Where the window will land.
                ZonePreview {
                    zone: root.previewZone()
                }

                OverviewLayer {
                    anchors.fill: parent
                    visible: root.mode === "overview"
                    rects: root.overviewRects
                    clients: root.candidates
                    selectedIndex: root.stripFocus ? -1 : root.overviewIndex
                    stripFocused: root.stripFocus || root.candidates.length === 0
                    morph: root.overviewMorph
                    progress: root.overviewT
                    topInset: root.monitor ? root.monitor.reserved[1] : 0
                    wallpaper: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
                    toplevelFor: root.toplevelFor
                    iconFor: root.iconFor
                    screens: root.workspaceScreens
                    previewFor: root.previewDrop
                    switchTick: root.overviewSwitchTick
                    switchDir: root.overviewSwitchDir
                    onMainChosen: function(name) { root.setMainMonitor(name); }
                    workspaceId: root.overviewWorkspace
                    emptyText: qsTr("Nenhuma janela neste workspace")
                    onSelect: function(index) { root.overviewIndex = index; }
                    onActivated: function(address) { root.focusWindow(address); }
                    onWorkspaceChosen: function(entry) { root.chooseWorkspaceEntry(entry); }
                    onWorkspaceActivated: function(entry) { root.goToWorkspace(entry.id); }
                    onWorkspaceReorder: function(from, to) { root.swapWorkspaces(from, to); }
                    onMoveRequested: function(address, workspaceId) { root.moveWindowToWorkspace(address, workspaceId); }
                }

                LayoutPicker {
                    visible: root.mode === "picker" || root.mode === "drag"
                    layouts: root.layouts
                    count: root.pickerCount
                    card: root.cardRect()
                    thumbRects: root.thumbRects()
                    zoneRect: root.zoneThumbRect
                    hoverLayout: root.hoverLayout
                    hoverZone: root.hoverZone
                    interactive: root.mode === "picker"
                    onEntered: function(layout, zone) {
                        root.hoverLayout = layout;
                        root.hoverZone = zone;
                    }
                    onExited: function(layout, zone) {
                        if (root.hoverLayout === layout && root.hoverZone === zone) {
                            root.hoverLayout = -1;
                            root.hoverZone = -1;
                        }
                    }
                    onChosen: function(layout, zone) { root.chooseZone(layout, zone); }
                }

                // Snap assist: outline the zones already filled, and offer windows for the next.
                Repeater {
                    model: root.mode === "assist" ? root.filledZones().length : 0

                    ZoneOutline {
                        required property int index
                        zone: root.filledZones()[index]
                    }
                }

                AssistPanel {
                    zone: root.assistZoneRect()
                    clients: root.assistPageItems()
                    rects: root.assistCardRects()
                    page: root.assistPageIndex()
                    pages: root.assistPageCount()
                    toplevelFor: root.toplevelFor
                    iconFor: root.iconFor
                    onPicked: function(address) { root.assistPick(address); }
                    onPageRequested: function(page) { root.assistPage = page; }
                }
            }
        }
    }
}
