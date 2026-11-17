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
import "controllers"
import "lib/layouts.js" as Layouts
import "lib/drag.js" as Drag
import "lib/monitors.js" as Monitors
import "lib/motion.js" as Motion
import "lib/navigation.js" as Navigation
import "lib/autosnap.js" as AutoSnap
import "lib/dispatch.js" as Dispatch
import "lib/hyprctl.js" as Hyprctl
import "lib/mode.js" as Mode
import "lib/windows.js" as Windows
import "lib/overview.js" as Overview
import "lib/settings.js" as Settings
import "lib/shortcuts.js" as Shortcuts
import "lib/style.js" as SystemStyle
import "lib/workspaces.js" as Workspaces

// The plugin's overlay: snap layouts for Hyprland windows (the picker, dragging to the
// top, an edge or a corner, and snap assist), and an Alt+Tab style window overview.
// WinSaico, the third product, is controllers/WinSaico.qml; the options and the lists
// of WinSaico workspaces are read by controllers/Store.qml, for this file and for the
// bar button alike.
//
// Ways in:
//   - Super+Z, if given (Hyprland event "io.github.n0rthstar88.snap-layouts:toggle"),
//     opens the layout picker for the focused window.
//   - Dragging a window to the top edge of a screen shows the same picker;
//     releasing over a zone snaps the window there. The plugin installs the
//     mouse binds for this itself (lua/hook.lua); see "Options and binds".
//   - Dragging against a side edge or a corner (or the very top) shows a preview
//     of a half, a quarter or the whole usable area; releasing snaps there.
//   - "...:overview" (Alt+Tab) opens the window overview.
//   - omarchy-shell snaplayouts toggle | overview | product | layout | uninstall
//
// After the first window is placed, "snap assist" offers the other open
// windows for each remaining zone of the chosen layout.
//
// Structure: decisions live in lib/ (pure JS, unit tested), views in components/,
// non-visual concerns in controllers/, and this file keeps the state machine and the
// Hyprland I/O. See docs/ARCHITECTURE.md.
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
    // What the drag has seen so far (lib/drag.js): which edge it waits at, and since when.
    property var dragState: Drag.initial()

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
    // lua/overview-mode.lua); this remembers that we asked, and when.
    property bool modal: false
    property double modalSince: 0
    // A window to select again after the next refresh (it moved).
    property string pendingSelect: ""
    // The overview shows the workspace the monitor is showing, so its windows
    // can travel to and from their real places; otherwise they fade.
    readonly property bool overviewMorph: root.closingIntoWorkspace
        || (root.monitor ? root.overviewWorkspace === root.monitor.workspaceId : true)
    // The overview is closing because a window, or a workspace, was chosen: the
    // workspace being looked at is about to be the one on screen, so its windows
    // travel to their real places instead of just fading where they are.
    property bool closingIntoWorkspace: false
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
        duration: Motion.TOKENS.open.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.TOKENS.open.curve
    }
    // Closing runs the opening backwards: the windows travel back to their
    // places, and only then does the overview go away.
    NumberAnimation {
        id: closeAnim
        target: root
        property: "overviewT"
        to: 0
        duration: Motion.TOKENS.close.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.TOKENS.close.curve
        onFinished: root.landed()
    }

    // Thumbnails in rows of equal height; the maths is in lib/overview.js.
    function overviewLayout(list, area) {
        var windows = list.map(function(c) {
            return { at: c.at, size: c.size, monitor: root.monitorById(c.monitor) || root.monitor };
        });
        return Overview.layoutRows(windows, area, Overview.LAYOUT);
    }



    function toggleOverview() {
        if (root.mode === "overview")
            root.close();
        else if (!root.opened && root.overviewOn)
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
        root.closingIntoWorkspace = false;
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

    // The area windows can use on this monitor, in the overlay's own coordinates:
    // what the bar and docks leave free, less the gap to the screen edge.
    readonly property var usableBounds: {
        if (!root.monitor)
            return null;
        var a = Workspaces.usableArea(root.monitor, root.style.outer);
        return { x: a.x - root.monitor.x, y: a.y - root.monitor.y, w: a.w, h: a.h };
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
        root.overviewRects = root.overviewLayout(list, Overview.area(m, root.workspaceScreens.length > 0));
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
        // The key that closes it is the overview's own key (see lua/overview-mode.lua).
        var exit = Settings.overviewKey(root.options);
        Quickshell.execDetached(["hyprctl", "eval", "snap_layouts_overview_shortcut = "
            + (exit !== "" ? JSON.stringify(exit) : "nil")
            + "; dofile(" + JSON.stringify(root.pluginDir + "/lua/overview-mode.lua") + ")"]);
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
        root.closingIntoWorkspace = id === root.overviewWorkspace;
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
        root.closingIntoWorkspace = true;
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
        lua = lua.join("; ");
        // Nothing moves the focus (and so nothing to wait for) when the window already has it.
        var already = root.activeIpc && root.activeIpc.address === address;
        if (root.mode !== "overview" || already) {
            Quickshell.execDetached(["hyprctl", "eval", lua]);
            root.close();
            return;
        }
        // The overview holds the keyboard exclusively while it is open, and Hyprland
        // ignores a request to focus a window until it lets go: asked too early the
        // focus stays where it was and comes back to it when the overview closes. So
        // the cards travel back to their windows first, then it lets go of the keyboard,
        // asks for the focus, and goes away when Hyprland says it has moved (landed(),
        // focusStep, the activewindowv2 event). The window is raised under the card
        // that sits exactly on it, so nothing shows twice.
        root.pendingFocus = { address: address, lua: lua };
        root.close();
    }

    // The window the overview is about to focus, once its cards are home: { address, lua }.
    property var pendingFocus: null
    // The overview has let go of the keyboard so that the focus can move.
    property bool releasing: false

    // The cards are back on their windows.
    function landed() {
        if (!root.pendingFocus) {
            root.hide();
            return;
        }
        root.releasing = true;
        focusStep.attempts = 0;
        focusStep.restart();
    }

    // Asks for the focus once the keyboard is let go of, and again if Hyprland has not
    // answered by the next look; after a few looks the overview goes away regardless.
    Timer {
        id: focusStep
        interval: 40
        property int attempts: 0
        onTriggered: {
            if (!root.pendingFocus)
                return;
            if (attempts >= 4) {
                root.hide();
                return;
            }
            attempts++;
            Quickshell.execDetached(["hyprctl", "eval", root.pendingFocus.lua]);
            restart();
        }
    }

    // The overview panel covers the usable area of the screen, with a margin.

    property int assistLayout: -1
    property var assistZones: []
    property var placedAddresses: []
    readonly property int assistZone: assistZones.length > 0 ? assistZones[0] : -1
    property var candidates: []

    // Between the button's press and release events.
    property bool buttonDown: false

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
        return Overview.layoutRows(windows, area, Overview.ASSIST_LAYOUT);
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
        else if (root.snapOn)
            root.requestSnapshot("picker");
    }

    // Shell overlay contract (omarchy-shell shell summon io.github.n0rthstar88.snap-layouts).
    function open(payload) {
        if (!root.opened && root.snapOn)
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
        root.closingIntoWorkspace = false;
        focusStep.stop();
        root.pendingFocus = null;
        root.releasing = false;
        root.stripFocus = false;
        root.leaveModal();
        root.mode = "";
        root.assistPage = 0;
        root.dragState = Drag.initial();
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

    Process {
        id: snapshotProc
        command: ["sh", "-c", "hyprctl -j monitors; printf '\\n@@SNAP@@\\n'; hyprctl -j clients; printf '\\n@@SNAP@@\\n'; hyprctl -j activewindow; printf '\\n@@SNAP@@\\n'; hyprctl -j plugin list; printf '\\n@@SNAP@@\\n'; hyprctl -j getoption general:gaps_out; printf '\\n@@SNAP@@\\n'; hyprctl -j getoption general:border_size"]
        stdout: StdioCollector {
            onStreamFinished: {
                var s = Hyprctl.parseSections(text);
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
            }
        }
    }

    // ---------- Dragging ----------
    //
    // The pointer comes from controllers/DragSensor.qml, what it is asking for from
    // lib/drag.js; this is where that is shown. A window is held against an edge or a
    // corner and the preview of its zone shows; held near the top, the picker does.

    DragSensor {
        id: sensor
        pluginDir: root.pluginDir
        onSample: (x, y, address) => root.handleDragSample(x, y, address)
        // A click, or a lost release: whatever the drag had opened goes away.
        onGaveUp: {
            if (root.mode === "drag" || root.mode === "edge")
                root.close();
        }
    }

    // Looks at the last sample again when the answer changes with time alone: the wait at
    // an edge running out while the pointer is held still.
    Timer {
        id: dragRecheck
        onTriggered: root.handleDragSample(root.lastSample.x, root.lastSample.y, root.lastSample.address)
    }
    property var lastSample: ({ x: 0, y: 0, address: "" })

    // Which zone the pointer is asking for, if it is against an edge/corner, as the
    // picker's layout and zone numbers.
    function edgeZone(edge) {
        return { layout: Layouts.INDEX[edge.layout], zone: edge.zone };
    }

    // Edge snap is a quick fit: place the window and stop, no snap assist.
    function quickSnap(layoutIndex, zoneIndex) {
        if (layoutIndex >= 0 && zoneIndex >= 0 && root.targetAddress)
            root.placeWindow(root.targetAddress, layoutIndex, zoneIndex);
        root.close();
    }

    function handleDragSample(x, y, address) {
        if (!root.buttonDown)
            return;
        root.lastSample = { x: x, y: y, address: address };
        var r = Drag.step(root.dragState, { x: x, y: y }, {
            now: Date.now(),
            mode: root.mode,
            current: root.monitor ? root.monitor.name : "",
            monitors: root.monitors,
            snapOn: root.snapOn,
            edge: root.edgeOptions,
            dwellMs: root.edgeDwellMs,
            topDistance: root.dragTriggerDistance
        });
        root.dragState = r.state;
        if (r.recheck) {
            dragRecheck.interval = r.recheck;
            dragRecheck.restart();
        } else {
            dragRecheck.stop();
        }

        if (r.act === "edge-hover" || r.act === "edge-open") {
            var zone = root.edgeZone(r.edge);
            if (r.act === "edge-open") {
                root.monitor = r.monitor;
                root.targetAddress = address;
                root.mode = "edge";
            }
            root.hoverLayout = zone.layout;
            root.hoverZone = zone.zone;
        } else if (r.act === "edge-close") {
            root.hoverLayout = -1;
            root.hoverZone = -1;
            root.close();
        } else if (r.act === "picker-open") {
            root.monitor = r.monitor;
            root.targetAddress = address;
            root.mode = "drag";
            root.pickerHover(x, y);
        } else if (r.act === "picker-monitor") {
            root.monitor = r.monitor;
            root.pickerHover(x, y);
        } else if (r.act === "picker-hover") {
            root.pickerHover(x, y);
        }
    }

    // The picker is open for a dragged window: which zone is the pointer over? Leaving
    // the card (or going to another screen) closes it.
    function pickerHover(x, y) {
        var m = root.monitorAt(x, y);
        var lx = x - root.monitor.x;
        var ly = y - root.monitor.y;
        var cr = root.cardRect();
        if (!m || ly > cr.y + cr.h + 120 || m.name !== root.monitor.name) {
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
        if (!root.snapOn || root.mode === "picker" || root.mode === "assist")
            return;
        root.buttonDown = true;
        root.dragState = Drag.initial();
        root.requestSnapshot("press");
        sensor.start();
    }

    function handleRelease() {
        if (!root.buttonDown)
            return;
        root.buttonDown = false;
        sensor.stop();
        dragRecheck.stop();
        root.dragState = Drag.initial();
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
            // The window the overview asked for has the focus: it can go away now.
            if (event && event.name === "activewindowv2") {
                if (root.pendingFocus && root.releasing && "0x" + event.data === root.pendingFocus.address)
                    root.hide();
                return;
            }
            if (event && event.name === "openwindow") {
                // ADDRESS,WORKSPACE,CLASS,TITLE
                var opened = String(event.data).split(",");
                winsaico.mosaicCheck(parseInt(opened[1]));
                winsaico.fitNotice(opened[0], opened[1]);
                return;
            }
            if (event && event.name === "movewindowv2") {
                // ADDRESS,WORKSPACEID,WORKSPACENAME
                var moved = String(event.data).split(",");
                winsaico.fitNotice(moved[0], moved[1]);
                return;
            }
            if (event && event.name === "closewindow") {
                // Only a window the plugin placed leaves a gap to close.
                if (winsaico.placed("0x" + String(event.data).split(",")[0]))
                    winsaico.fitSoon();
                return;
            }
            if (event && event.name === "workspacev2") {
                winsaico.mosaicCheck(parseInt(event.data));
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
            else if (event.data === "io.github.n0rthstar88.snap-layouts:layout-next")
                winsaico.layoutAction("next");
            else if (event.data === "io.github.n0rthstar88.snap-layouts:layout-back")
                winsaico.layoutAction("back");
            else if (event.data === "io.github.n0rthstar88.snap-layouts:autofit-toggle")
                winsaico.setAutoFit(!root.options.autoFit);
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
        // Set a shortcut the plugin binds for you: `shortcut picker "SUPER + Z"`,
        // `shortcut overview "ALT + TAB"`, `shortcut layout "SUPER + L"`, `shortcut
        // layoutBack "SUPER + ALT + L"` and `shortcut autoFit "<keys>"`; `off` removes it
        // (the layout and overview keys then go back to their defaults).
        function shortcut(name: string, keys: string): string {
            if (["picker", "overview", "layout", "layoutBack", "autoFit"].indexOf(name) === -1)
                return "expected picker, overview, layout, layoutBack or autoFit";
            var spec = keys.trim();
            if (spec === "off")
                spec = "";
            else if (!Shortcuts.valid(spec))
                return "not a shortcut Hyprland understands: " + keys + " (write it like \"SUPER + Z\")";
            if (!root.setShortcut(name, spec))
                return "could not save the shortcut";
            return spec === "" ? name + " shortcut removed"
                : name + " shortcut set to " + spec + " (anything else bound to those keys is replaced while the plugin runs)";
        }
        // The three products, each with a switch: `product winsaico on`, `product overview
        // off`, `product snap toggle`, or `status` for the current state of one.
        function product(name: string, state: string): string {
            var current = { winsaico: root.options.winsaico, overview: root.options.overview, snap: root.options.snap }[name];
            if (current === undefined)
                return "expected winsaico, overview or snap";
            if (state === "status")
                return name + " " + (current ? "on" : "off");
            if (state !== "on" && state !== "off" && state !== "toggle")
                return "expected on, off, toggle or status";
            var want = state === "toggle" ? !current : state === "on";
            if (!root.setProduct(name, want))
                return "could not save the choice";
            return name + " " + (want ? "on" : "off");
        }
        // The workspace's layout, the way Super+L sets it: `layout next` or `back`, or
        // a mode by name: tiling, scrolling, floating or winsaico.
        function layout(action: string): string {
            var names = { next: "next", back: "back", tiling: "dwindle", scrolling: "scrolling", floating: "floating", mosaic: "mosaic", winsaico: "mosaic" };
            if (!names[action])
                return "expected next, back, tiling, scrolling, floating or winsaico";
            // Choosing WinSaico turns the product on; any other mode needs it on already.
            if (!root.options.winsaico) {
                if (names[action] !== "mosaic")
                    return "WinSaico is off";
                root.setProduct("winsaico", true);
            }
            winsaico.layoutAction(names[action]);
            return "ok";
        }
        // The default layout of workspaces that have none of their own, as Appearance >
        // Workspace Layout sets it: tiling, scrolling, floating or winsaico.
        function defaultLayout(name: string): string {
            var mode = name === "winsaico" ? "mosaic" : name;
            if (!root.options.winsaico && mode === "mosaic")
                root.setProduct("winsaico", true);
            return winsaico.setDefault(mode) ? "ok" : "expected tiling, scrolling, floating or winsaico";
        }
        // Auto-fit in WinSaico: `autofit on`, `off`, `toggle` or `status`. Turning it
        // on fits the windows of the mosaic workspaces at once.
        function autofit(state: string): string {
            if (state === "on" || state === "off" || state === "toggle") {
                var want = state === "toggle" ? !root.options.autoFit : state === "on";
                if (!winsaico.setAutoFit(want))
                    return "could not save the choice";
                return "auto-fit " + (want ? "on" : "off");
            }
            if (state !== "status")
                return "expected on, off, toggle or status";
            return "auto-fit " + (root.options.autoFit ? "on" : "off");
        }
        // Take the plugin out of the system before it is removed: every product off (so
        // the keys it bound go back at the next reload), WinSaico's rows out of the menu,
        // and the lists it keeps in Omarchy's state folder forgotten. Then `omarchy plugin
        // remove`. Windows WinSaico floated stay where they are.
        function uninstall(): string {
            store.save({ winsaico: false, overview: false, snap: false });
            Quickshell.execDetached(["sh", "-c", Dispatch.forgetCommand(store.stateDir)]);
            return "off: the keys come back at the next reload; now run: omarchy plugin remove " + root.pluginId;
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

    // ---------- The plugin's three products ----------
    //
    // WinSaico (a workspace mode, with auto-fit) is controllers/WinSaico.qml. The other
    // two are here: Snapping (the picker, dragging to the top, an edge or a corner) and
    // Alt+Tab (the window overview). Each has a switch of its own in the options.

    // What both entry points read: the options and the lists of WinSaico workspaces.
    Store {
        id: store
        shell: root.shell
        onLoadedChanged: if (loaded) root.settingsReady()
    }

    // WinSaico's rows in Omarchy's Appearance > Workspace Layout menu, while it is on.
    MenuRows {
        wanted: root.options.winsaico
        ready: store.loaded
    }

    WinSaico {
        id: winsaico
        enabled: root.options.winsaico
        store: store
        shell: root.shell
        pluginDir: root.pluginDir
        innerGap: root.innerGap
    }

    // ---------- Options and binds ----------

    // The options (shell.json, validated by lib/settings.js) are read by the store,
    // which the bar button reads too. The three products each have a switch:
    // `winsaico`, `overview` (Alt+Tab) and `snap`.
    readonly property var options: store.options
    readonly property bool snapOn: root.options.snap
    readonly property bool overviewOn: root.options.overview
    readonly property string mainMonitor: root.options.mainMonitor

    readonly property string pluginDir: String((root.manifest && root.manifest.__sourceDir)
        || (Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.pluginId))
    readonly property string hookPath: root.pluginDir + "/lua/hook.lua"
    readonly property string bindDescription: "io.github.n0rthstar88.snap-layouts drag"
    readonly property var dragButtons: ["mouse:272", "mouse:273"]

    // Switch a product on or off: "winsaico", "overview" or "snap".
    function setProduct(name, on) {
        if (["winsaico", "overview", "snap"].indexOf(name) === -1)
            return false;
        var change = {};
        change[name] = on;
        return store.save(change);
    }

    onSnapOnChanged: {
        if (!root.snapOn && (root.mode === "picker" || root.mode === "assist"))
            root.close();
        root.ensureDragBinds();
    }
    onOverviewOnChanged: {
        if (!root.overviewOn && root.mode === "overview")
            root.close();
    }
    onOptionsChanged: root.ensureShortcutBinds()

    function settingsReady() {
        root.ensureLayerRule();
        root.ensureDragBinds();
        root.ensureShortcutBinds();
        winsaico.ensureHook();
    }

    // The overlay is not faded out by Hyprland (lua/layer.lua). A reload drops the rule.
    function ensureLayerRule() {
        Quickshell.execDetached(["hyprctl", "eval", "dofile(" + JSON.stringify(root.pluginDir + "/lua/layer.lua") + ")"]);
    }

    // Adds the drag binds for any button that lacks them. Binds are only ever
    // added, never removed (see lua/hook.lua for why). When Snapping is off
    // they stay put and handlePress() ignores them.
    function ensureDragBinds() {
        if (!store.loaded || !root.snapOn)
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
                if (missing.length === 0 || !root.snapOn)
                    return;
                Quickshell.execDetached(["hyprctl", "eval", "snap_layouts_buttons = "
                    + JSON.stringify(missing).replace("[", "{").replace("]", "}")
                    + "; dofile(" + JSON.stringify(root.hookPath) + ")"]);
            }
        }
    }

    // ---- The plugin's shortcuts ----
    //
    // The layout keys (WinSaico), the overview's key and the picker's, when set. Each
    // product that is on binds its keys; one that is off binds none, so Omarchy's own
    // come back. See lib/shortcuts.js for what is bound, left alone, or needs a reload.

    property var warnedShortcuts: ({})
    property double lastShortcutReload: 0

    function ensureShortcutBinds() {
        if (!store.loaded)
            return;
        if (!shortcutsProc.running)
            shortcutsProc.running = true;
    }

    Process {
        id: shortcutsProc
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
                var plan = Shortcuts.plan(binds, Settings.wantedShortcuts(root.options, Shortcuts.layoutKeys(binds)));
                plan.skipped.forEach(function(item) {
                    var key = item.name + item.spec;
                    if (root.warnedShortcuts[key])
                        return;
                    root.warnedShortcuts[key] = true;
                    console.warn(root.pluginId + ": the " + item.name + " shortcut " + item.spec + " is not bound: " + item.reason + ".");
                });
                // Hyprland can't safely remove a bind, so a changed or dropped
                // shortcut is cleared by reloading the config; the reload event
                // brings us back here to bind what is wanted.
                if (plan.reload) {
                    var wait = 5000 - (Date.now() - root.lastShortcutReload);
                    if (wait <= 0) {
                        root.lastShortcutReload = Date.now();
                        Quickshell.execDetached(["hyprctl", "reload"]);
                    } else {
                        // Reloaded a moment ago: look again as soon as that is over.
                        shortcutRetry.interval = wait + 200;
                        shortcutRetry.restart();
                    }
                    return;
                }
                if (Object.keys(plan.add).length > 0) {
                    Object.keys(plan.replace).forEach(function(name) {
                        console.info(root.pluginId + ": the " + name + " shortcut " + plan.add[name] + " replaces: " + plan.replace[name].join(", "));
                    });
                    Quickshell.execDetached(["hyprctl", "eval", Shortcuts.assignLua(plan.add, plan.replace)
                        + "; dofile(" + JSON.stringify(root.pluginDir + "/lua/shortcuts.lua") + ")"]);
                }
            }
        }
    }

    Timer {
        id: shortcutRetry
        onTriggered: root.ensureShortcutBinds()
    }

    // Set (or, with "", remove) one of the plugin's shortcuts, saved in shell.json.
    function setShortcut(name, spec) {
        var change = {};
        change[name + "Shortcut"] = spec;
        return store.save(change);
    }

    // Other plugins' Keybind:remove() also deletes the drag binds when they share a
    // button (Window controls does on startup), so check again now and then.
    Timer {
        interval: 30000
        repeat: true
        running: store.loaded
        onTriggered: {
            root.ensureDragBinds();
            root.ensureShortcutBinds();
        }
    }

    // Lets a config reload finish before checking which binds survived it.
    Timer {
        id: reloadCheck
        interval: 500
        onTriggered: {
            root.ensureLayerRule();
            root.ensureDragBinds();
            root.ensureShortcutBinds();
            winsaico.ensureHook();
        }
    }

    function setMainMonitor(name) {
        store.save({ mainMonitor: name });
        root.refreshStrips();
    }

    // ---------- UI ----------

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    Loader {
        active: root.opened && root.monitor !== null
        sourceComponent: overlayComponent
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
            WlrLayershell.keyboardFocus: (root.mode === "drag" || root.mode === "edge" || root.releasing) ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
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
                    bounds: root.usableBounds
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
