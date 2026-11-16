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
    property real progress: 1           // 0..1, the opening animation
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

    signal select(int index)
    signal activated(string address)
    signal workspaceChosen(var entry)
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

    // Wallpaper, dimmed: hides the real windows behind the thumbnails.
    Item {
        anchors.fill: parent
        anchors.topMargin: layer.topInset
        opacity: layer.progress

        Rectangle {
            anchors.fill: parent
            color: Commons.Color.background
        }

        Image {
            anchors.fill: parent
            source: layer.wallpaper
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: layer.dim
        }
    }

    // The strips: the main screen big, the others small, always in the same order.
    Row {
        id: band
        visible: layer.screens.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: layer.topInset + 14
        spacing: 36
        opacity: layer.progress
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
                    text: screen.modelData.name
                    color: Util.withAlpha(Commons.Color.popups.text, screen.main ? 0.75 : 0.6)
                    font.family: Qt.application.font.family
                    font.pixelSize: Style.font.body - 3
                }

                WorkspaceStrip {
                    id: strip
                    entries: screen.modelData.entries
                    selectedId: layer.workspaceId
                    aspect: screen.modelData.aspect
                    thumbHeight: screen.main ? (layer.screens.length > 1 ? 68 : 76) : 40
                    dropId: layer.dropId
                    drop: layer.dropInfo
                    dropToplevel: layer.dragIndex >= 0 && layer.clients[layer.dragIndex]
                        ? layer.toplevelFor(layer.clients[layer.dragIndex].address) : null
                    toplevelFor: layer.toplevelFor
                    onChosen: function(entry) { layer.workspaceChosen(entry); }
                }
            }
        }
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
            selected: index === layer.selectedIndex
            dragged: index === layer.dragIndex
            onHovered: layer.select(index)
            onActivated: layer.activated(client.address)
            onDragStarted: function(sx, sy) { layer.updateDrag(index, sx, sy); }
            onDragMoved: function(sx, sy) { layer.updateDrag(index, sx, sy); }
            onDropped: function(sx, sy) { layer.finishDrag(index, sx, sy); }
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

        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            anchors.topMargin: 3
            anchors.bottomMargin: -9
            radius: 14
            color: "black"
            opacity: 0.45
        }

        WindowPicture {
            anchors.fill: parent
            toplevel: ghost.client ? layer.toplevelFor(ghost.client.address) : null
            iconSource: ghost.client ? layer.iconFor(ghost.client) : ""
            cornerRadius: 10
            backdrop: Util.withAlpha(Commons.Color.popups.background, 0.9)
        }
    }
}
