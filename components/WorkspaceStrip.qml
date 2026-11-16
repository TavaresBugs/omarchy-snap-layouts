pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util

// A row of workspace thumbnails. Each one shows what the workspace really holds:
// its windows, drawn small at their real positions with their live picture.
// Empty workspaces are dimmed. The selected one gets a thin neutral ring.
// Presentation only: it reports clicks as a signal.
//
//   entries: from Workspaces.buildStrip -> [{ id, label, windows: [{x, y, w, h, address}], count }]
Item {
    id: strip

    property var entries: []
    property int selectedId: 0
    property real aspect: 16 / 9
    property int thumbHeight: 76
    property var toplevelFor: function(address) { return null; }

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
                readonly property bool selected: modelData.id === strip.selectedId
                readonly property bool empty: modelData.count === 0
                readonly property int inset: 3

                width: Math.round(strip.thumbHeight * strip.aspect)
                height: strip.thumbHeight
                radius: 8
                color: Util.withAlpha(Commons.Color.popups.background, 0.82)
                border.color: Util.withAlpha(Commons.Color.popups.text, selected ? 0.9 : 0.16)
                border.width: selected ? 2 : 1
                scale: selected || mouse.containsMouse ? 1.05 : 1
                opacity: selected || mouse.containsMouse ? 1 : (empty ? 0.55 : 0.88)
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                // The windows, at their real positions, with their live picture.
                Repeater {
                    model: thumb.modelData.windows

                    WindowPicture {
                        required property var modelData
                        x: thumb.inset + modelData.x * (thumb.width - 2 * thumb.inset)
                        y: thumb.inset + modelData.y * (thumb.height - 2 * thumb.inset)
                        width: Math.max(4, modelData.w * (thumb.width - 2 * thumb.inset))
                        height: Math.max(4, modelData.h * (thumb.height - 2 * thumb.inset))
                        toplevel: strip.toplevelFor(modelData.address)
                        cornerRadius: 3
                        backdrop: Util.withAlpha(Commons.Color.background, 0.8)
                        fallbackIconSize: 0
                    }
                }

                // Workspace label, as in the bar.
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 4
                    width: label.implicitWidth + 10
                    height: 16
                    radius: 8
                    color: Util.withAlpha(Commons.Color.background, 0.78)

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: thumb.modelData.label
                        color: Commons.Color.popups.text
                        font.family: Qt.application.font.family
                        font.pixelSize: Style.font.body - 3
                        font.weight: Font.DemiBold
                    }
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
