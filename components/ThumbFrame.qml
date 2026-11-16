import QtQuick
import QtQuick.Effects
import "Util.js" as Util
import qs.Commons as Commons // qmllint disable import

// The frame every thumbnail shares, big or small: a soft shadow, the content
// clipped to rounded corners, and a thin ring drawn above the content, so
// nothing inside can spill over the outline. The overview cards and the
// workspace thumbnails are both built on it, so they look like one family.
//
// Colours come from the theme, the way Omarchy's own image picker does it: the
// accent for the selected one, a faint rim for the others.
//
//   ThumbFrame {
//       radius: 10
//       emphasized: selected       // the selection: accent ring, deeper shadow
//       current: viewed            // the one being looked at, while another thing has focus: soft accent ring
//       fill: "#22000000"          // behind the content
//       Image { anchors.fill: parent; ... }   // children are the content
//   }
Item {
    id: frame

    property int radius: 10
    property bool emphasized: false
    property bool current: false
    property color fill: "transparent"
    // 0..1: how far the frame has come off the desktop (the shadow grows with it).
    property real depth: 1
    // Children declared inside a ThumbFrame go into the clipped area.
    default property alias content: clip.data

    readonly property color accent: Commons.Color.imagePicker.selectedBorder
    readonly property color rim: Commons.Color.imagePicker.unselectedBorder

    // One soft shadow, sized from the frame so a small thumbnail and a large card
    // get the same look: blur and drop are fixed fractions of the height.
    RectangularShadow {
        anchors.fill: parent
        radius: frame.radius
        blur: Math.round(Math.max(6, Math.min(30, frame.height * 0.09)))
        offset: Qt.vector2d(0, Math.max(2, Math.min(10, frame.height * 0.028)))
        color: Qt.rgba(0, 0, 0, (frame.emphasized ? 0.6 : 0.4) * frame.depth)
        Behavior on color { ColorAnimation { duration: 140 } }
    }

    Item {
        id: clip
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
            color: frame.fill
        }
    }

    // The mask has to be an invisible item with a layer.
    Rectangle {
        id: roundedMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        radius: frame.radius
        color: "black"
    }

    // The ring: the accent when selected, a softer accent for the workspace being
    // looked at, a faint rim otherwise.
    Rectangle {
        anchors.fill: parent
        radius: frame.radius
        color: "transparent"
        border.width: frame.emphasized || frame.current ? 2 : 1
        border.color: frame.emphasized ? frame.accent
            : (frame.current ? Util.withAlpha(frame.accent, 0.5) : frame.rim)
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }
}
