pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "../lib/overview.js" as Overview
import "Util.js" as Util

// Snap assist: after a window is snapped, this panel fills the next empty zone
// and offers the other windows for it, as paged thumbnails. Pure presentation:
// the plugin passes the windows and the page in, and gets the pick back.
Rectangle {
    id: panel

    property var zone: null             // { x, y, w, h } in the overlay's coordinates
    property var clients: []            // windows on offer
    property int page: 0
    property int pageSize: 6
    property var toplevelFor: function(address) { return null; }
    property var iconFor: function(client) { return ""; }

    signal picked(string address)
    signal pageRequested(int page)

    readonly property int pages: Math.max(1, Math.ceil(clients.length / pageSize))
    readonly property int currentPage: Math.min(page, pages - 1)
    readonly property var pageItems: clients.slice(currentPage * pageSize, (currentPage + 1) * pageSize)

    function goToPage(target) {
        panel.pageRequested(Math.max(0, Math.min(panel.pages - 1, target)));
    }

    visible: zone !== null
    x: zone ? zone.x : 0
    y: zone ? zone.y : 0
    width: zone ? zone.w : 0
    height: zone ? zone.h : 0
    radius: Style.cornerRadius + 10
    color: Util.withAlpha(Commons.Color.popups.background, 0.95)
    border.color: Util.withAlpha(Commons.Color.accent, 0.75)
    border.width: 2

    MouseArea {
        anchors.fill: parent
    }

    // ---- Header: title and the keys that work ------------------------------------
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 18
        height: 30

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Escolha uma janela para este espaço")
            color: Commons.Color.popups.text
            font.family: Qt.application.font.family
            font.pixelSize: Style.font.body + 3
            font.weight: Font.DemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            visible: panel.width > 560

            Repeater {
                model: panel.pages > 1
                    ? [{ k: "1–6", t: qsTr("escolher") }, { k: "←  →", t: qsTr("página") },
                       { k: "Tab", t: qsTr("pular") }, { k: "Esc", t: qsTr("concluir") }]
                    : [{ k: "1–6", t: qsTr("escolher") }, { k: "Tab", t: qsTr("pular") },
                       { k: "Esc", t: qsTr("concluir") }]

                Row {
                    id: hint
                    required property var modelData
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 22
                        width: keyLabel.implicitWidth + 14
                        radius: 6
                        color: Util.withAlpha(Commons.Color.popups.text, 0.1)
                        border.color: Util.withAlpha(Commons.Color.popups.text, 0.18)
                        border.width: 1

                        Text {
                            id: keyLabel
                            anchors.centerIn: parent
                            text: hint.modelData.k
                            color: Commons.Color.popups.text
                            font.family: Qt.application.font.family
                            font.pixelSize: Style.font.body - 1
                            font.weight: Font.Medium
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: hint.modelData.t
                        color: Util.withAlpha(Commons.Color.popups.text, 0.65)
                        font.family: Qt.application.font.family
                        font.pixelSize: Style.font.body - 1
                    }
                }
            }
        }
    }

    // ---- Thumbnails -----------------------------------------------------------------
    Item {
        id: area
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        anchors.topMargin: 14

        readonly property real gridW: width
        readonly property real gridH: height - (panel.pages > 1 ? 36 : 0)
        readonly property int n: panel.pageItems.length
        // 2 side by side, 2+1, 2x2, 3+2, 3+3; a very wide zone gets one row.
        readonly property int cols: n > 1 && gridW / Math.max(1, gridH) > 2.2
            ? Math.min(n, 4) : Overview.columnsFor(n)
        readonly property int rows: Math.max(1, Math.ceil(n / cols))
        readonly property real cellW: Math.min(gridW / cols, 380)
        readonly property real cellH: Math.min(gridH / rows, 300)
        property int hoveredIndex: -1

        WheelHandler {
            onWheel: function(event) {
                panel.goToPage(panel.currentPage + (event.angleDelta.y < 0 ? 1 : -1));
            }
        }

        Repeater {
            model: panel.pageItems

            Item {
                id: cell
                required property var modelData
                required property int index
                readonly property int row: Math.floor(index / area.cols)
                readonly property int inRow: row === area.rows - 1 ? area.n - row * area.cols : area.cols
                readonly property bool hovered: mouse.containsMouse

                x: (area.gridW - inRow * area.cellW) / 2 + (index % area.cols) * area.cellW
                y: (area.gridH - area.rows * area.cellH) / 2 + row * area.cellH
                width: area.cellW
                height: area.cellH
                opacity: area.hoveredIndex < 0 || hovered ? 1 : 0.7
                Behavior on opacity { NumberAnimation { duration: 140 } }
                onHoveredChanged: {
                    if (hovered)
                        area.hoveredIndex = index;
                    else if (area.hoveredIndex === index)
                        area.hoveredIndex = -1;
                }

                Item {
                    id: holder
                    anchors.fill: parent
                    anchors.margins: 14
                    anchors.bottomMargin: 40

                    Item {
                        id: thumb
                        readonly property real aspect: cell.modelData.size && cell.modelData.size[1] > 0
                            ? cell.modelData.size[0] / cell.modelData.size[1] : 1.6
                        width: Math.min(holder.width, holder.height * aspect)
                        height: width / aspect
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: cell.hovered ? -5 : 0
                        scale: cell.hovered ? 1.06 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                        // Soft shadow, and an accent glow while hovered.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            anchors.topMargin: 4
                            anchors.bottomMargin: -8
                            radius: 16
                            color: "black"
                            opacity: 0.28
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -10
                            radius: 22
                            color: Commons.Color.accent
                            opacity: cell.hovered ? 0.4 : 0
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                        }

                        WindowPicture {
                            anchors.fill: parent
                            toplevel: panel.toplevelFor(cell.modelData.address)
                            iconSource: panel.iconFor(cell.modelData)
                            cornerRadius: 12
                            backdrop: Util.withAlpha(Commons.Color.background, 0.7)
                            fallbackIconSize: 64
                        }

                        // Hover ring, drawn above the picture.
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: "transparent"
                            border.color: Commons.Color.accent
                            border.width: 3
                            opacity: cell.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }

                        // App icon on the bottom edge.
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height - height * 0.5
                            width: 46
                            height: 46
                            source: panel.iconFor(cell.modelData)
                            sourceSize.width: 92
                            sourceSize.height: 92
                        }

                        // Shortcut number, per page.
                        Rectangle {
                            x: 8
                            y: 8
                            width: 20
                            height: 20
                            radius: 10
                            color: Util.withAlpha(Commons.Color.background, 0.78)
                            Text {
                                anchors.centerIn: parent
                                text: String(cell.index + 1)
                                color: Commons.Color.popups.text
                                font.family: Qt.application.font.family
                                font.pixelSize: Style.font.body - 2
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                // Window title, shown on hover.
                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    horizontalAlignment: Text.AlignHCenter
                    text: String(cell.modelData.title || cell.modelData.class || qsTr("Janela"))
                    color: Commons.Color.popups.text
                    font.family: Qt.application.font.family
                    font.pixelSize: Style.font.body
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    opacity: cell.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.picked(cell.modelData.address)
                }
            }
        }

        // ---- Page controls ------------------------------------------------------------
        Row {
            visible: panel.pages > 1
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            height: 26

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                font.pixelSize: 22
                color: Util.withAlpha(Commons.Color.popups.text, panel.currentPage > 0 ? 0.9 : 0.3)
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: panel.goToPage(panel.currentPage - 1) }
            }

            Repeater {
                model: panel.pages

                Rectangle {
                    required property int index
                    anchors.verticalCenter: parent.verticalCenter
                    width: index === panel.currentPage ? 20 : 8
                    height: 8
                    radius: 4
                    color: index === panel.currentPage
                        ? Commons.Color.accent
                        : Util.withAlpha(Commons.Color.popups.text, 0.35)
                    Behavior on width { NumberAnimation { duration: 120 } }
                    MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: panel.goToPage(parent.index) }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                font.pixelSize: 22
                color: Util.withAlpha(Commons.Color.popups.text, panel.currentPage < panel.pages - 1 ? 0.9 : 0.3)
                MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: panel.goToPage(panel.currentPage + 1) }
            }
        }
    }
}
