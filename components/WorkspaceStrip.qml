pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util

// A row of small workspace thumbnails, each drawn as the outlines of its
// windows, with an empty slot at the end for a new workspace. The selected one
// gets a thin neutral ring. Presentation only: it reports clicks as a signal.
//
//   entries: from Workspaces.buildStrip -> [{ id, isNew, windows: [{x, y, w, h}], count }]
Item {
    id: strip

    property var entries: []
    property int selectedId: 0
    property real aspect: 16 / 9
    readonly property int thumbHeight: 46

    signal chosen(var entry)

    implicitWidth: row.implicitWidth
    implicitHeight: thumbHeight

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12

        Repeater {
            model: strip.entries

            Rectangle {
                id: thumb
                required property var modelData
                readonly property bool selected: !modelData.isNew && modelData.id === strip.selectedId

                width: Math.round(strip.thumbHeight * strip.aspect)
                height: strip.thumbHeight
                radius: 8
                color: Util.withAlpha(Commons.Color.popups.background, modelData.isNew ? 0.35 : 0.8)
                border.color: Util.withAlpha(Commons.Color.popups.text, selected ? 0.9 : 0.16)
                border.width: selected ? 2 : 1
                scale: selected || mouse.containsMouse ? 1.05 : 1
                opacity: selected || mouse.containsMouse ? 1 : 0.85
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                // The workspace's windows, as outlines.
                Repeater {
                    model: thumb.modelData.windows

                    Rectangle {
                        required property var modelData
                        x: 4 + modelData.x * (thumb.width - 8)
                        y: 4 + modelData.y * (thumb.height - 8)
                        width: Math.max(3, modelData.w * (thumb.width - 8))
                        height: Math.max(3, modelData.h * (thumb.height - 8))
                        radius: 2
                        color: Util.withAlpha(Commons.Color.popups.text, 0.28)
                        border.color: Util.withAlpha(Commons.Color.popups.text, 0.45)
                        border.width: 1
                    }
                }

                // Empty slot: a plus.
                Text {
                    visible: thumb.modelData.isNew
                    anchors.centerIn: parent
                    text: "+"
                    color: Util.withAlpha(Commons.Color.popups.text, 0.6)
                    font.pixelSize: 22
                }

                // Workspace number.
                Text {
                    visible: !thumb.modelData.isNew
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    text: String(thumb.modelData.id)
                    color: Util.withAlpha(Commons.Color.popups.text, 0.7)
                    font.family: Qt.application.font.family
                    font.pixelSize: Style.font.body - 3
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: strip.chosen(thumb.modelData)
                }
            }
        }
    }
}
