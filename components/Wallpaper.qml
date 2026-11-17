import QtQuick
import QtQuick.Effects

// The desktop's wallpaper, blurred, laid out over a whole screen exactly as the desktop
// draws it. The overview's backdrop and the strip behind the bar both show a piece of
// one of these, so the two are the same picture and meet without a seam, whatever the
// bar in front of the strip looks like (clear, glassy or solid). Give it the size of the
// screen and clip it to the piece wanted.
Item {
    id: wallpaper

    property color base: "black"        // behind the picture, until it is decoded
    property url source: ""
    property real blur: 0.7             // 0 sharp .. 1 the most the effect gives

    // The picture is a little larger than the screen, so the blur has something to draw
    // from at the edges (the overscan is cut off by whoever clips this).
    readonly property int overscan: 48

    Rectangle {
        anchors.fill: parent
        color: wallpaper.base
    }

    Image {
        x: -wallpaper.overscan
        y: -wallpaper.overscan
        width: wallpaper.width + 2 * wallpaper.overscan
        height: wallpaper.height + 2 * wallpaper.overscan
        source: wallpaper.source
        fillMode: Image.PreserveAspectCrop
        // Decoded before the first frame (cached afterwards), so the wallpaper can't
        // pop in halfway through an animation.
        asynchronous: false
        cache: true
        layer.enabled: wallpaper.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: wallpaper.blur
            blurMax: wallpaper.overscan
            autoPaddingEnabled: false
        }
    }
}
