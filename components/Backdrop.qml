import QtQuick

// The frosted wallpaper behind the overview, for the screen below the bar.
//
// The blurred wallpaper (components/Wallpaper.qml), laid out over the full screen as the
// desktop draws it, with the theme's background over it as strong as `dim` (none, now).
// Only the part below the bar is painted. The bar is left as it is, with its own colours,
// and the overlay lets it take clicks; a strip under it, in SnapLayouts.qml, shows the
// same wallpaper, so the two meet without a seam. It has no corners of its own to show:
// nothing is visible outside it.
Item {
    id: backdrop

    property color base: "black"
    property color tint: "black"        // laid over the blurred wallpaper, `dim` strong
    property url wallpaper: ""
    property real dim: 0
    property real blur: 0.7             // 0 sharp .. 1 the most the effect gives
    property int topInset: 0            // height of the bar, left unpainted

    // Where the picture starts: a pixel above the bar's bottom edge. The bar's height
    // times the screen's scale is rarely a whole number of pixels, so painting from
    // exactly there leaves a row between the bar and the picture where the window
    // underneath shows, and the accent of its border draws a thin line across the screen.
    readonly property int paintFrom: Math.max(0, backdrop.topInset - 1)

    Item {
        y: backdrop.paintFrom
        width: parent.width
        height: parent.height - backdrop.paintFrom
        clip: true

        Wallpaper {
            y: -backdrop.paintFrom
            width: backdrop.width
            height: backdrop.height
            base: backdrop.base
            source: backdrop.wallpaper
            blur: backdrop.blur
        }

        Rectangle {
            anchors.fill: parent
            color: backdrop.tint
            opacity: backdrop.dim
        }
    }
}
