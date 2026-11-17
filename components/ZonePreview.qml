import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util
import "../lib/shape.js" as Shape
import "../lib/motion.js" as Motion

// The tinted preview of where a window will land. `zone` is { x, y, w, h } in the
// overlay's coordinates, or null to hide it. Moving between zones slides.
Rectangle {
    id: preview

    // Every corner comes from lib/shape.js, from the windows' own rounding.
    readonly property var shape: Shape.radii(Style.cornerRadius)
    property int borderWidth: -1
    readonly property var ring: Shape.ring(preview.borderWidth)

    property var zone: null

    visible: zone !== null
    x: zone ? zone.x : 0
    y: zone ? zone.y : 0
    width: zone ? zone.w : 0
    height: zone ? zone.h : 0
    radius: preview.shape.zone
    color: Util.withAlpha(Commons.Color.accent, Shape.ALPHA.tintStrong)
    border.color: Util.withAlpha(Commons.Color.accent, Shape.ALPHA.active)
    border.width: preview.ring.strong
    opacity: visible ? 1 : 0
    scale: visible ? 1 : 0.96

    Behavior on opacity { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.fade) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.fade); easing.type: Easing.OutCubic } }
    Behavior on x { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.quick); easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.quick); easing.type: Easing.OutCubic } }
    Behavior on width { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.quick); easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.quick); easing.type: Easing.OutCubic } }
}
