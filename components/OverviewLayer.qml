pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util

// The window overview (Alt+Tab view): a clean backdrop with every window as a
// thumbnail. The backdrop starts below the bar, so the bar stays visible.
//
// Pure presentation. The plugin supplies the layout and the selection and
// listens for what the user picks:
//
//   OverviewLayer {
//       rects: ...          // from Overview.layoutRows
//       clients: ...        // the windows, same order as rects
//       selectedIndex: ...
//       onSelect: function(index) { ... }
//       onActivated: function(address) { ... }
//   }
Item {
    id: layer

    property var rects: []
    property var clients: []
    property int selectedIndex: 0
    property real progress: 1           // 0..1, the opening (and closing) animation
    property bool morph: true           // false: the windows fade instead of travelling
    property bool stripFocused: false   // the keyboard is on the workspace strip
    property int topInset: 0            // height of the bar to leave uncovered
    property url wallpaper: ""
    property real dim: 0.55

    // One strip per screen (hidden when empty), the main screen first and big,
    // the others small: [{ name, main, workspaceId, aspect, entries }].
    property var screens: []
    // The workspace being looked at.
    property int workspaceId: 0
    property string emptyText: ""

    // Lookups the plugin provides, so this file needs no knowledge of Hyprland.
    property var toplevelFor: function(address) { return null; }
    property var iconFor: function(client) { return ""; }
    // What dropping a window on a workspace would look like, or null:
    // function(workspaceId, address) -> { windows, slot }.
    property var previewFor: function(workspaceId, address) { return null; }

    // The dim is quick (the real windows must be hidden while the cards still sit on
    // them) and eased, so it neither jumps nor lingers.
    readonly property real dimProgress: {
        var t = Math.min(1, layer.progress * 1.8);
        return t * t * (3 - 2 * t);
    }

    readonly property real stripProgress: {
        var t = Math.max(0, Math.min(1, (layer.progress - 0.55) / 0.45));
        return t * t * (3 - 2 * t);
    }

    signal select(int index)
    signal activated(string address)
    signal workspaceChosen(var entry)
    signal workspaceActivated(var entry)
    signal workspaceReorder(int from, int to)
    // The name of a screen was clicked: make it the main one.
    signal mainChosen(string name)

    // Bumped to play the switch animation when the view moves to another
    // workspace: the windows slide in from `switchDir` (-1, 0 or 1) and fade in.
    property int switchTick: 0
    property int switchDir: 0
    onSwitchTickChanged: switchAnim.restart()
    // A card was dropped on a workspace of the strips.
    signal moveRequested(string address, int workspaceId)

    // ---- Dragging a window onto a workspace ----
    property int dragIndex: -1
    property point dragPoint: Qt.point(0, 0)
    property int dropId: -1
    property var dropInfo: null

    function workspaceAt(p) {
        for (var i = 0; i < screenRepeater.count; i++) {
            var strip = screenRepeater.itemAt(i).strip;
            var q = strip.mapFromItem(layer, p.x, p.y);
            var id = strip.idAt(q.x, q.y);
            if (id > 0)
                return id;
        }
        return -1;
    }

    function updateDrag(index, sx, sy) {
        dragIndex = index;
        dragPoint = layer.mapFromItem(null, sx, sy);
        dropId = layer.workspaceAt(dragPoint);
        var c = clients[index];
        dropInfo = dropId > 0 && c ? layer.previewFor(dropId, c.address) : null;
    }

    function finishDrag(index, sx, sy) {
        updateDrag(index, sx, sy);
        var c = clients[index];
        var target = dropId;
        dragIndex = -1;
        dropId = -1;
        dropInfo = null;
        if (c && target > 0 && Number(c.workspace.id) !== target)
            layer.moveRequested(c.address, target);
    }

    // Wallpaper, dimmed, over the whole screen (the bar stays visible, dimmed like
    // the rest). It reaches the edges, so no window border can show around it.
    // Quick: while the cards are still leaving their windows, the real ones are
    // already hidden behind it, so they aren't seen twice.
    Backdrop {
        anchors.fill: parent
        opacity: layer.dimProgress
        topInset: layer.topInset
        base: Commons.Color.background
        wallpaper: layer.wallpaper
        dim: layer.dim
    }

    // The strips: the main screen big, the others small, always in the same order.
    Row {
        id: band
        visible: layer.screens.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        // The strip comes in last and leaves first: it drops in from above once the
        // cards have mostly arrived, and is gone before they head back, so a card
        // returning to a window that fills the screen never grows under it.
        y: layer.topInset + 14 - 18 * (1 - layer.stripProgress)
        spacing: 36
        opacity: layer.stripProgress
        z: 20

        Repeater {
            id: screenRepeater
            model: layer.screens

            Column {
                id: screen
                required property var modelData
                readonly property bool main: modelData.main
                property alias strip: strip
                spacing: 3
                y: (band.height - height) / 2

                Text {
                    id: nameLabel
                    text: screen.main ? screen.modelData.name + "  ·  " + qsTr("principal")
                        : (nameArea.containsMouse ? screen.modelData.name + "  ·  " + qsTr("tornar principal") : screen.modelData.name)
                    color: Util.withAlpha(Commons.Color.popups.text, screen.main || nameArea.containsMouse ? 0.85 : 0.6)
                    font.family: Qt.application.font.family
                    font.pixelSize: Style.font.body - 3

                    MouseArea {
                        id: nameArea
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: !screen.main
                        hoverEnabled: true
                        cursorShape: screen.main ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: layer.mainChosen(screen.modelData.name)
                    }
                }

                WorkspaceStrip {
                    id: strip
                    entries: screen.modelData.entries
                    selectedId: layer.workspaceId
                    aspect: screen.modelData.aspect
                    thumbHeight: screen.main ? (layer.screens.length > 1 ? 68 : 76) : 40
                    focused: layer.stripFocused
                    dropId: layer.dropId
                    drop: layer.dropInfo
                    dropToplevel: layer.dragIndex >= 0 && layer.clients[layer.dragIndex]
                        ? layer.toplevelFor(layer.clients[layer.dragIndex].address) : null
                    toplevelFor: layer.toplevelFor
                    onChosen: function(entry) { layer.workspaceChosen(entry); }
                    onActivated: function(entry) { layer.workspaceActivated(entry); }
                    onReorderRequested: function(from, to) { layer.workspaceReorder(from, to); }
                }
            }
        }
    }

    // The windows. This is what slides and fades when the view changes workspace.
    Item {
        id: cards
        anchors.fill: parent

        ParallelAnimation {
            id: switchAnim
            NumberAnimation { target: cards; property: "x"; from: layer.switchDir * 56; to: 0; duration: 240; easing.type: Easing.OutCubic }
            NumberAnimation { target: cards; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutQuad }
        }

        // A workspace with no windows.
        Text {
            visible: layer.visible && layer.rects.length === 0
            anchors.centerIn: parent
            text: layer.emptyText
            color: Util.withAlpha(Commons.Color.popups.text, 0.7)
            font.family: Qt.application.font.family
            font.pixelSize: Style.font.body + 3
            opacity: layer.progress
        }

        Repeater {
            // Nothing is built (and no window captured) while the layer is hidden.
            model: layer.visible ? layer.rects.length : 0

            OverviewCard {
                required property int index
                rect: layer.rects[index]
                client: layer.clients[index] ?? null
                toplevel: client ? layer.toplevelFor(client.address) : null
                iconSource: client ? layer.iconFor(client) : ""
                progress: layer.progress
                morph: layer.morph
                delay: index === layer.selectedIndex || layer.rects.length < 2 ? 0 : 0.18 * index / (layer.rects.length - 1)
                selected: index === layer.selectedIndex
                dragged: index === layer.dragIndex
                onHovered: layer.select(index)
                onActivated: layer.activated(client.address)
                onDragStarted: function(sx, sy) { layer.updateDrag(index, sx, sy); }
                onDragMoved: function(sx, sy) { layer.updateDrag(index, sx, sy); }
                onDropped: function(sx, sy) { layer.finishDrag(index, sx, sy); }
            }
        }
    }

    // The window being carried, following the pointer.
    Item {
        id: ghost
        readonly property var rect: layer.dragIndex >= 0 ? layer.rects[layer.dragIndex] : null
        readonly property var client: layer.dragIndex >= 0 ? layer.clients[layer.dragIndex] : null
        visible: rect !== null && client !== null
        width: 200
        height: rect ? Math.max(60, Math.round(width * rect.h / Math.max(1, rect.w))) : 0
        x: layer.dragPoint.x - width / 2
        y: layer.dragPoint.y - height / 2
        // Smaller over a workspace, as if dropping into it.
        scale: layer.dropId > 0 ? 0.6 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        opacity: 0.92
        z: 100

        ThumbFrame {
            anchors.fill: parent
            radius: 10
            emphasized: true

            WindowPicture {
                anchors.fill: parent
                toplevel: ghost.client ? layer.toplevelFor(ghost.client.address) : null
                iconSource: ghost.client ? layer.iconFor(ghost.client) : ""
                cornerRadius: 0
                backdrop: Util.withAlpha(Commons.Color.popups.background, 0.9)
            }
        }
    }
}
