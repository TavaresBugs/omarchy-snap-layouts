import QtQuick
import QtQuick.Effects

// A dimmed wallpaper that fills its area, with rounded corners when `radius` is
// above zero so it can match the system's window corners.
Item {
    id: backdrop

    property color base: "black"
    property url wallpaper: ""
    property real dim: 0.55
    property int radius: 0

    Item {
        anchors.fill: parent
        layer.enabled: backdrop.radius > 0
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: roundedMask
            maskThresholdMin: 0.3
            maskSpreadAtMin: 0.3
        }

        Rectangle {
            anchors.fill: parent
            color: backdrop.base
        }

        Image {
            anchors.fill: parent
            source: backdrop.wallpaper
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: backdrop.dim
        }
    }

    // The mask has to be an invisible item with a layer.
    Rectangle {
        id: roundedMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        radius: backdrop.radius
        color: "black"
    }
}
