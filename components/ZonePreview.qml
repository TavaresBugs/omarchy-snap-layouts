import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util

// The tinted preview of where a window will land. `zone` is { x, y, w, h } in the
// overlay's coordinates, or null to hide it. Moving between zones slides.
Rectangle {
    id: preview

    property var zone: null

    visible: zone !== null
    x: zone ? zone.x : 0
    y: zone ? zone.y : 0
    width: zone ? zone.w : 0
    height: zone ? zone.h : 0
    radius: Style.cornerRadius + 2
    color: Util.withAlpha(Commons.Color.accent, 0.22)
    border.color: Util.withAlpha(Commons.Color.accent, 0.9)
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
