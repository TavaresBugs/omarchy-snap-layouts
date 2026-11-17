import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util
import "../lib/motion.js" as Motion
import "../lib/shape.js" as Shape

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
    // Cards leave their windows one after another, so the selected one leads and
    // the rest follow (see lib/motion.js).
    property real delay: 0
    readonly property real travel: morph ? Motion.travel(progress, delay) : 1
    // The icon and title come in only once the card has nearly arrived.
    readonly property real chrome: morph ? Motion.clamp01((travel - Motion.TOKENS.chromeFrom) / (1 - Motion.TOKENS.chromeFrom)) : progress
    // The area windows can use, in this card's coordinates, or null. The selected
    // card is enlarged and lifted only as far as it has room for inside it.
    property var bounds: null

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

    // On its window it has the window's corners; settled, the card's.
    readonly property var shape: Shape.radii(Style.cornerRadius)
    property int borderWidth: -1

    x: rect ? rect.rx + (rect.x - rect.rx) * travel : 0
    y: rect ? rect.ry + (rect.y - rect.ry) * travel : 0
    width: rect ? rect.rw + (rect.w - rect.rw) * travel : 0
    height: rect ? rect.rh + (rect.h - rect.rh) * travel : 0
    z: selected ? 10 : 0
    opacity: (morph ? 1 : progress) * (dragged ? Shape.ALPHA.muted : (selected ? 1 : Shape.ALPHA.active))
    Behavior on opacity { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.fade) } }

    // The selected card is lifted and a little larger, but only as far as the room
    // around it allows, and only as far as it has travelled: on its window (travel
    // 0) it is exactly that window's size and place, whether or not there is room
    // around the window, so it does not jump when the overview goes away; settled in
    // the overview it gets the full emphasis. Nothing here depends on the layout.
    property real lift: selected ? 1 : 0
    Behavior on lift { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.settle); easing.type: Easing.OutCubic } }
    readonly property var room: Motion.emphasis(x, y, width, height, bounds)
    scale: 1 + (room.scale - 1) * lift * travel
    transform: Translate { y: -card.room.lift * card.lift * card.travel }

    ThumbFrame {
        anchors.fill: parent
        radius: Shape.between(card.shape.zone, card.shape.card, card.travel)
        borderWidth: card.borderWidth
        emphasized: card.selected
        depth: card.travel

        WindowPicture {
            anchors.fill: parent
            toplevel: card.toplevel
            iconSource: card.client ? card.iconSource : ""
            cornerRadius: 0
            backdrop: Util.withAlpha(Commons.Color.popups.background, Shape.ALPHA.placeholder)
        }
    }

    // App icon on the bottom edge.
    Image {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height * 0.5
        width: 40
        height: 40
        opacity: card.chrome
        scale: 0.8 + 0.2 * card.chrome
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
        color: Util.withAlpha(Commons.Color.popups.text, 1)
        // Over the blurred wallpaper, which can be as bright as the text.
        style: Text.Outline
        styleColor: Util.withAlpha(Commons.Color.background, Shape.ALPHA.outline)
        font.family: Qt.application.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        opacity: card.selected ? card.chrome : 0
        Behavior on opacity { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.quick) } }
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
