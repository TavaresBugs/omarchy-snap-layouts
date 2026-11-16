import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util

// A thin outline around a zone that is already filled (snap assist).
// `zone` is { x, y, w, h } in the overlay's coordinates, or null to hide it.
Rectangle {
    property var zone: null

    visible: zone !== null
    x: zone ? zone.x : 0
    y: zone ? zone.y : 0
    width: zone ? zone.w : 0
    height: zone ? zone.h : 0
    color: "transparent"
    radius: Style.cornerRadius
    border.color: Util.withAlpha(Commons.Color.popups.text, 0.35)
    border.width: 1
}
