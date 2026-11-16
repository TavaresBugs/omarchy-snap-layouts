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

    // Workspace strip (hidden when `workspaces` is empty).
    property var workspaces: []
    property int workspaceId: 0
    property real monitorAspect: 16 / 9
    property string emptyText: ""

    // Lookups the plugin provides, so this file needs no knowledge of Hyprland.
    property var toplevelFor: function(address) { return null; }
    property var iconFor: function(client) { return ""; }

    signal select(int index)
    signal activated(string address)
    signal workspaceChosen(var entry)

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

    WorkspaceStrip {
        visible: layer.workspaces.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: layer.topInset + 14
        width: implicitWidth
        entries: layer.workspaces
        selectedId: layer.workspaceId
        aspect: layer.monitorAspect
        opacity: layer.progress
        z: 20
        onChosen: function(entry) { layer.workspaceChosen(entry); }
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
            onHovered: layer.select(index)
            onActivated: layer.activated(client.address)
        }
    }
}
