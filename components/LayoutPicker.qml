pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util
import "../lib/shape.js" as Shape
import "../lib/motion.js" as Motion

// The card of layout thumbnails at the top of the screen. Every zone of every
// layout can be hovered and picked. Geometry comes from lib/layouts.js through
// the properties below; this file only draws and reports what the pointer does.
Rectangle {
    id: picker

    // Every corner comes from lib/shape.js, from the windows' own rounding.
    readonly property var shape: Shape.radii(Style.cornerRadius)
    property int borderWidth: -1
    readonly property var ring: Shape.ring(picker.borderWidth)

    property var layouts: []            // Layouts.LAYOUTS
    property int count: 0               // how many of them to show
    property var card: ({ x: 0, y: 0, w: 0, h: 0 })     // Layouts.cardRect(...)
    property var thumbRects: []         // Layouts.thumbRect(...) for each layout
    property var zoneRect: function(layout, zone, w, h) { return { x: 0, y: 0, w: 0, h: 0 }; }
    property int hoverLayout: -1
    property int hoverZone: -1
    property bool interactive: true     // false while a window is being dragged

    signal entered(int layout, int zone)
    signal exited(int layout, int zone)
    signal chosen(int layout, int zone)

    x: card.x
    y: card.y
    width: card.w
    height: card.h
    radius: picker.shape.panel
    color: Util.withAlpha(Commons.Color.popups.background, Shape.ALPHA.solid)
    border.color: Util.withAlpha(Commons.Color.accent, Shape.ALPHA.soft)
    border.width: picker.ring.rim
    opacity: visible ? 1 : 0
    scale: visible ? 1 : 0.94
    transformOrigin: Item.Top
    Behavior on opacity { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.fade) } }
    Behavior on scale { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.pop); easing.type: Easing.OutBack } }

    // Swallow clicks on the card background.
    MouseArea {
        anchors.fill: parent
    }

    Repeater {
        model: picker.count

        Rectangle {
            id: thumb
            required property int index
            readonly property var r: picker.thumbRects[index]
            readonly property bool hot: picker.hoverLayout === index
            x: r.x - picker.card.x
            y: r.y - picker.card.y
            width: r.w
            height: r.h
            radius: picker.shape.thumb
            color: hot ? Util.withAlpha(Commons.Color.accent, Shape.ALPHA.tint)
                       : Util.withAlpha(Commons.Color.popups.text, Shape.ALPHA.faint)
            border.color: hot ? Util.withAlpha(Commons.Color.accent, Shape.ALPHA.active)
                              : Util.withAlpha(Commons.Color.popups.text, Shape.ALPHA.line)
            border.width: hot ? picker.ring.strong : picker.ring.rim
            Behavior on color { ColorAnimation { duration: Style.duration(Motion.TOKENS.dur.hover) } }
            Behavior on border.color { ColorAnimation { duration: Style.duration(Motion.TOKENS.dur.hover) } }

            Repeater {
                model: picker.layouts[thumb.index].length

                Rectangle {
                    id: zone
                    required property int index
                    readonly property var zr: picker.zoneRect(thumb.index, index, thumb.width, thumb.height)
                    readonly property bool hot: picker.hoverLayout === thumb.index && picker.hoverZone === index
                    x: zr.x
                    y: zr.y
                    width: zr.w
                    height: zr.h
                    radius: picker.shape.mini
                    color: hot ? Commons.Color.accent : Util.withAlpha(Commons.Color.popups.text, Shape.ALPHA.muted)
                    Behavior on color { ColorAnimation { duration: Style.duration(Motion.TOKENS.dur.hover) } }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -2
                        enabled: picker.interactive
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: picker.entered(thumb.index, zone.index)
                        onExited: picker.exited(thumb.index, zone.index)
                        onClicked: picker.chosen(thumb.index, zone.index)
                    }
                }
            }
        }
    }
}
