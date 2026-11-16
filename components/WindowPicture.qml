import QtQuick
import QtQuick.Effects
import Quickshell.Wayland

// A window's picture, with rounded corners when `cornerRadius` is above zero (use
// zero inside a ThumbFrame, which clips it), falling back to the app icon when
// the window cannot be captured (minimized, or not yet available).
//
// Rounding uses a mask effect, the way Omarchy's own image picker does it; the
// mask has to be a visible-false item with a layer, hence the separate rectangle.
Item {
    id: picture

    property var toplevel: null             // Hyprland toplevel to capture, or null
    property string iconSource: ""
    property int cornerRadius: 10
    property color backdrop: "#99000000"    // shown until the capture arrives
    property int fallbackIconSize: 56

    readonly property bool hasContent: capture.hasContent

    Item {
        anchors.fill: parent
        layer.enabled: picture.cornerRadius > 0
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: roundedMask
            maskThresholdMin: 0.3
            maskSpreadAtMin: 0.3
        }

        Rectangle {
            anchors.fill: parent
            color: picture.backdrop
        }

        ScreencopyView {
            id: capture
            anchors.fill: parent
            captureSource: picture.toplevel && picture.toplevel.wayland ? picture.toplevel.wayland : null
            live: false
            paintCursor: false
        }
    }

    Rectangle {
        id: roundedMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        radius: picture.cornerRadius
        color: "black"
    }

    Image {
        anchors.centerIn: parent
        visible: !capture.hasContent && picture.iconSource !== ""
        width: Math.min(picture.fallbackIconSize, parent.height * 0.5)
        height: width
        source: picture.iconSource
        sourceSize.width: picture.fallbackIconSize * 2
        sourceSize.height: picture.fallbackIconSize * 2
    }
}
