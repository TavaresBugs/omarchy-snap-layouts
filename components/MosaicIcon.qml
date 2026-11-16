import QtQuick

// The WinSaico figure: four squares in a two by two grid, the outer corners of the
// whole figure rounded and the inner ones nearly square, so it reads as one rounded
// block cut into four. Drawn rather than taken from the icon font so the rounding is
// exact at any size. It takes its colour and size from the caller.
Item {
    id: root

    property color color: "white"
    // The side of the whole figure.
    property real size: 20
    // The space between the squares, and the roundness of the outer and inner corners.
    property real gap: Math.max(1, Math.round(size * 0.1))
    property real outer: size * 0.3
    property real inner: size * 0.05

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    readonly property real cell: (size - gap) / 2

    Repeater {
        model: 4

        Rectangle {
            required property int index
            x: (index % 2) * (root.cell + root.gap)
            y: Math.floor(index / 2) * (root.cell + root.gap)
            width: root.cell
            height: root.cell
            color: root.color
            topLeftRadius: index === 0 ? root.outer : root.inner
            topRightRadius: index === 1 ? root.outer : root.inner
            bottomLeftRadius: index === 2 ? root.outer : root.inner
            bottomRightRadius: index === 3 ? root.outer : root.inner
        }
    }
}
