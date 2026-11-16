import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util

// One window in the overview: its picture in a ThumbFrame, the app icon sitting
// on its bottom edge, and the title below it when selected. It knows nothing
// about the plugin: data comes in as properties and user actions go out as
// signals.
Item {
    id: card

    // Where the thumbnail ends up (x, y, w, h) and where the real window is
    // (rx, ry, rw, rh), as produced by Overview.layoutRows.
    property var rect: null
    // 0 = the card sits exactly on the real window, 1 = settled in the overview.
    property real progress: 1
    // False when the real window isn't on screen (another workspace is being
    // looked at): the card then fades instead of travelling from its place.
    property bool morph: true
    readonly property real travel: morph ? progress : 1

    property var client: null           // the window's `hyprctl clients` entry
    property var toplevel: null         // its Hyprland toplevel, for the live picture
    property string iconSource: ""
    property bool selected: false
    // While this card is being dragged to a workspace it stays behind, faded.
    property bool dragged: false

    signal hovered()
    signal activated()
    // Drag and drop: scene coordinates of the pointer.
    signal dragStarted(real sx, real sy)
    signal dragMoved(real sx, real sy)
    signal dropped(real sx, real sy)

    readonly property int cornerRadius: 10

    x: rect ? rect.rx + (rect.x - rect.rx) * travel : 0
    y: rect ? rect.ry + (rect.y - rect.ry) * travel : 0
    width: rect ? rect.rw + (rect.w - rect.rw) * travel : 0
    height: rect ? rect.rh + (rect.h - rect.rh) * travel : 0
    z: selected ? 10 : 0
    opacity: (morph ? 1 : progress) * (dragged ? 0.35 : (selected ? 1 : 0.9))
    scale: selected ? 1.05 : 1
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    transform: Translate {
        y: card.selected ? -6 : 0
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    ThumbFrame {
        anchors.fill: parent
        radius: card.cornerRadius
        emphasized: card.selected

        WindowPicture {
            anchors.fill: parent
            toplevel: card.toplevel
            iconSource: card.client ? card.iconSource : ""
            cornerRadius: 0
            backdrop: Util.withAlpha(Commons.Color.popups.background, 0.9)
        }
    }

    // App icon on the bottom edge.
    Image {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height * 0.5
        width: 40
        height: 40
        source: card.iconSource
        sourceSize.width: 80
        sourceSize.height: 80
    }

    // Title, only for the selected window.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height + 24
        width: Math.max(parent.width, 200)
        horizontalAlignment: Text.AlignHCenter
        text: card.client ? String(card.client.title || card.client.class || "") : ""
        color: Util.withAlpha(Commons.Color.popups.text, 0.9)
        font.family: Qt.application.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        opacity: card.selected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: card.dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        // A press that travels further than this is a drag, not a click.
        readonly property int threshold: 8
        property point pressPoint
        property bool moved: false

        function scene(m) {
            return mouse.mapToItem(null, m.x, m.y);
        }

        onEntered: card.hovered()
        onPressed: function(m) {
            pressPoint = scene(m);
            moved = false;
        }
        onPositionChanged: function(m) {
            if (!pressed)
                return;
            var p = scene(m);
            if (!moved && Math.hypot(p.x - pressPoint.x, p.y - pressPoint.y) > threshold) {
                moved = true;
                card.dragStarted(p.x, p.y);
            }
            if (moved)
                card.dragMoved(p.x, p.y);
        }
        onReleased: function(m) {
            if (moved) {
                var p = scene(m);
                card.dropped(p.x, p.y);
            }
        }
        onClicked: {
            if (!moved)
                card.activated();
        }
    }
}
