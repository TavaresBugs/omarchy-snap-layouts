pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util
import "../lib/shape.js" as Shape
import "../lib/motion.js" as Motion

// Snap assist: after a window is snapped, this fills the next empty zone and
// offers the other windows for it. It looks like the overview (the same
// OverviewCard thumbnails) inside a quiet, neutral frame. Presentation only:
// the plugin passes in the windows, their layout and the page, and gets the
// pick back.
Rectangle {
    id: panel

    // Every corner comes from lib/shape.js, from the windows' own rounding.
    readonly property var shape: Shape.radii(Style.cornerRadius)
    property int borderWidth: -1
    readonly property var ring: Shape.ring(panel.borderWidth)
    // { pad, title, pager }: the panel's padding and the heights of the title and the pager,
    // from the theme's spacing (the same numbers the plugin lays the cards out with).
    property var metrics: ({ pad: 24, title: 16, pager: 26 })

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
    // The empty zone is where a window will sit: it has a window's corners.
    radius: panel.shape.zone
    // No filled frame: the cards sit on the frosted backdrop, in a faint outline.
    color: "transparent"
    border.color: Util.withAlpha(Commons.Color.popups.text, Shape.ALPHA.lineStrong)
    border.width: panel.ring.rim

    MouseArea {
        anchors.fill: parent
    }

    Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: panel.metrics.pad
        text: qsTr("Escolha uma janela para este espaço")
        color: Commons.Color.popups.text
        style: Text.Outline
        styleColor: Util.withAlpha(Commons.Color.background, Shape.ALPHA.outline)
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
            borderWidth: panel.borderWidth
            selected: index === panel.hoveredIndex
            onHovered: panel.hoveredIndex = index
            onActivated: { if (client) panel.picked(client.address); }
        }
    }

    // Page controls, only when there is more than one page.
    Row {
        visible: panel.pages > 1
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.panelPadding
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12
        height: panel.metrics.pager

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "‹"
            font.pixelSize: 22
            color: Util.withAlpha(Commons.Color.popups.text, panel.page > 0 ? Shape.ALPHA.active : Shape.ALPHA.muted)
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: panel.goToPage(panel.page - 1) }
        }

        Repeater {
            model: panel.pages

            Rectangle {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: index === panel.page ? 20 : 8
                height: 8
                radius: height / 2
                color: Util.withAlpha(Commons.Color.popups.text, index === panel.page ? Shape.ALPHA.active : Shape.ALPHA.muted)
                Behavior on width { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.quick) } }
                MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: panel.goToPage(parent.index) }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            font.pixelSize: 22
            color: Util.withAlpha(Commons.Color.popups.text, panel.page < panel.pages - 1 ? Shape.ALPHA.active : Shape.ALPHA.muted)
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: panel.goToPage(panel.page + 1) }
        }
    }
}
