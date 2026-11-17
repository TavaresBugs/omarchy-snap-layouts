import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util
import "../lib/shape.js" as Shape

// A zone of the snap assist that already holds a window: the window's picture in the
// same frame as an overview card (ThumbFrame), over the frosted backdrop. `zone` is the
// rectangle the window fills with its border (see Layouts.frameRect), so the frame's
// ring sits where the border is. `emphasized` is the focused one: the accent ring.
// `zone` is { x, y, w, h } in the overlay's coordinates, or null to hide it.
Item {
    id: outline

    // Every corner comes from lib/shape.js, from the windows' own rounding.
    readonly property var shape: Shape.radii(Style.cornerRadius)
    property int borderWidth: -1

    property var zone: null
    property var toplevel: null
    property string iconSource: ""
    property bool emphasized: false

    visible: zone !== null
    x: zone ? zone.x : 0
    y: zone ? zone.y : 0
    width: zone ? zone.w : 0
    height: zone ? zone.h : 0

    ThumbFrame {
        anchors.fill: parent
        radius: outline.shape.zone
        emphasized: outline.emphasized
        borderWidth: outline.borderWidth
        fill: Util.withAlpha(Commons.Color.popups.background, Shape.ALPHA.veil)

        WindowPicture {
            anchors.fill: parent
            toplevel: outline.toplevel
            iconSource: outline.iconSource
            cornerRadius: 0
            live: true
        }
    }
}
