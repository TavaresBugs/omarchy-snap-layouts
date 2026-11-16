import QtQuick

// The dimmed wallpaper behind the overview, as one piece for the whole screen.
//
// The wallpaper is laid out over the full screen, exactly as the desktop draws
// it, and only the part below the bar is painted, so the bar stays untouched
// and the picture lines up across it. One dim then covers everything, the bar
// strip included, so there is no seam between the bar and the rest. It has no
// corners of its own to show: nothing is visible outside it.
Item {
    id: backdrop

    property color base: "black"
    property url wallpaper: ""
    property real dim: 0.55
    property int topInset: 0            // height of the bar, left unpainted

    Item {
        y: backdrop.topInset
        width: parent.width
        height: parent.height - backdrop.topInset
        clip: true

        Item {
            y: -backdrop.topInset
            width: backdrop.width
            height: backdrop.height

            Rectangle {
                anchors.fill: parent
                color: backdrop.base
            }

            Image {
                anchors.fill: parent
                source: backdrop.wallpaper
                fillMode: Image.PreserveAspectCrop
                // Decoded before the first frame (cached afterwards), so the
                // wallpaper can't pop in halfway through an animation.
                asynchronous: false
                cache: true
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: backdrop.dim
    }
}
