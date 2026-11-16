pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util

// Snap assist: after a window is snapped, this fills the next empty zone and
// offers the other windows for it. It looks like the overview (the same
// OverviewCard thumbnails) inside a quiet, neutral frame. Presentation only:
// the plugin passes in the windows, their layout and the page, and gets the
// pick back.
Rectangle {
    id: panel

    property var zone: null             // { x, y, w, h } in the overlay's coordinates
    property var clients: []            // the windows on the current page
    property var rects: []              // their layout inside this panel (Overview.layoutRows)
    property int page: 0
    property int pages: 1
    property var toplevelFor: function(address) { return null; }
    property var iconFor: function(client) { return ""; }

    signal picked(string address)
    signal pageRequested(int page)

    property int hoveredIndex: -1

    function goToPage(target) {
        panel.pageRequested(Math.max(0, Math.min(panel.pages - 1, target)));
    }

    visible: zone !== null
    x: zone ? zone.x : 0
    y: zone ? zone.y : 0
    width: zone ? zone.w : 0
    height: zone ? zone.h : 0
    radius: Style.cornerRadius + 10
    color: Util.withAlpha(Commons.Color.popups.background, 0.82)
    border.color: Util.withAlpha(Commons.Color.popups.text, 0.14)
    border.width: 1

    MouseArea {
        anchors.fill: parent
    }

    Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: 24
        text: qsTr("Escolha uma janela para este espaço")
        color: Util.withAlpha(Commons.Color.popups.text, 0.8)
        font.family: Qt.application.font.family
        font.pixelSize: Style.font.body + 2
        font.weight: Font.Medium
    }

    WheelHandler {
        onWheel: function(event) {
            panel.goToPage(panel.page + (event.angleDelta.y < 0 ? 1 : -1));
        }
    }

    Repeater {
        model: panel.clients.length

        OverviewCard {
            required property int index
            rect: panel.rects[index] ?? null
            client: panel.clients[index] ?? null
            toplevel: client ? panel.toplevelFor(client.address) : null
            iconSource: client ? panel.iconFor(client) : ""
            progress: 1
            selected: index === panel.hoveredIndex
            onHovered: panel.hoveredIndex = index
            onActivated: { if (client) panel.picked(client.address); }
        }
    }

    // Page controls, only when there is more than one page.
    Row {
        visible: panel.pages > 1
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12
        height: 26

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            font.pixelSize: 22
            color: Util.withAlpha(Commons.Color.popups.text, panel.page > 0 ? 0.9 : 0.3)
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: panel.goToPage(panel.page - 1) }
        }

        Repeater {
            model: panel.pages

            Rectangle {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: index === panel.page ? 20 : 8
                height: 8
                radius: 4
                color: Util.withAlpha(Commons.Color.popups.text, index === panel.page ? 0.85 : 0.3)
                Behavior on width { NumberAnimation { duration: 120 } }
                MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: panel.goToPage(parent.index) }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            font.pixelSize: 22
            color: Util.withAlpha(Commons.Color.popups.text, panel.page < panel.pages - 1 ? 0.9 : 0.3)
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: panel.goToPage(panel.page + 1) }
        }
    }
}
