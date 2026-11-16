pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util

// The card of layout thumbnails at the top of the screen. Every zone of every
// layout can be hovered and picked. Geometry comes from lib/layouts.js through
// the properties below; this file only draws and reports what the pointer does.
Rectangle {
    id: picker

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
    radius: Style.cornerRadius + 10
    color: Util.withAlpha(Commons.Color.popups.background, 0.96)
    border.color: Util.withAlpha(Commons.Color.accent, 0.45)
    border.width: 1
    opacity: visible ? 1 : 0
    scale: visible ? 1 : 0.94
    transformOrigin: Item.Top
    Behavior on opacity { NumberAnimation { duration: 150 } }
    Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }

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
            radius: Style.cornerRadius + 2
            color: hot ? Util.withAlpha(Commons.Color.accent, 0.14)
                       : Util.withAlpha(Commons.Color.popups.text, 0.05)
            border.color: hot ? Util.withAlpha(Commons.Color.accent, 0.85)
                              : Util.withAlpha(Commons.Color.popups.text, 0.14)
            border.width: hot ? 2 : 1
            Behavior on color { ColorAnimation { duration: 90 } }
            Behavior on border.color { ColorAnimation { duration: 90 } }

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
                    radius: Math.max(3, Style.cornerRadius / 2 + 1)
                    color: hot ? Commons.Color.accent : Util.withAlpha(Commons.Color.popups.text, 0.28)
                    Behavior on color { ColorAnimation { duration: 80 } }

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
