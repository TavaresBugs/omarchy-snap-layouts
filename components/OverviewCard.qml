pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import

// One window in the overview: a live thumbnail with rounded corners and a soft
// shadow, the app icon sitting on its bottom edge, and the title below it when
// selected. It knows nothing about the plugin: data comes in as properties and
// user actions go out as signals.
Item {
    id: card

    // Where the thumbnail ends up (x, y, w, h) and where the real window is
    // (rx, ry, rw, rh), as produced by Overview.layoutRows.
    property var rect: null
    // 0 = the card sits exactly on the real window, 1 = settled in the overview.
    property real progress: 1

    property var client: null           // the window's `hyprctl clients` entry
    property var toplevel: null         // its Hyprland toplevel, for the live picture
    property string iconSource: ""
    property bool selected: false

    signal hovered()
    signal activated()

    readonly property int cornerRadius: 10
    readonly property var capture: toplevel && toplevel.wayland ? toplevel.wayland : null

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    x: rect ? rect.rx + (rect.x - rect.rx) * progress : 0
    y: rect ? rect.ry + (rect.y - rect.ry) * progress : 0
    width: rect ? rect.rw + (rect.w - rect.rw) * progress : 0
    height: rect ? rect.rh + (rect.h - rect.rh) * progress : 0
    z: selected ? 10 : 0
    opacity: selected ? 1 : 0.9
    scale: selected ? 1.05 : 1
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    transform: Translate {
        y: card.selected ? -6 : 0
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    // Soft shadow under the window, deeper for the selected one.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        anchors.topMargin: 3
        anchors.bottomMargin: -9
        radius: card.cornerRadius + 4
        color: "black"
        opacity: card.selected ? 0.5 : 0.3
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    // The window picture, clipped to rounded corners.
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: roundedMask
            maskThresholdMin: 0.3
            maskSpreadAtMin: 0.3
        }

        Rectangle {
            anchors.fill: parent
            color: card.withAlpha(Commons.Color.popups.background, 0.9)
        }

        ScreencopyView {
            id: picture
            anchors.fill: parent
            captureSource: card.capture
            live: false
            paintCursor: false
        }
    }

    Rectangle {
        id: roundedMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        radius: card.cornerRadius
        color: "black"
    }

    // Thin, quiet selection ring.
    Rectangle {
        anchors.fill: parent
        radius: card.cornerRadius
        color: "transparent"
        border.color: card.withAlpha(Commons.Color.popups.text, 0.85)
        border.width: 2
        opacity: card.selected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // Minimized or uncapturable windows show their icon in the middle.
    Image {
        anchors.centerIn: parent
        visible: !picture.hasContent && card.client !== null
        width: Math.min(56, parent.height * 0.5)
        height: width
        source: card.iconSource
        sourceSize.width: 112
        sourceSize.height: 112
    }

    // App icon on the bottom edge.
    Image {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height * 0.5
        width: 40
        height: 40
        source: card.iconSource
        sourceSize.width: 80
        sourceSize.height: 80
    }

    // Title, only for the selected window.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height + 24
        width: Math.max(parent.width, 200)
        horizontalAlignment: Text.AlignHCenter
        text: card.client ? String(card.client.title || card.client.class || "") : ""
        color: card.withAlpha(Commons.Color.popups.text, 0.9)
        font.family: Qt.application.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        opacity: card.selected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: card.hovered()
        onClicked: card.activated()
    }
}
