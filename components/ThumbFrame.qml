import QtQuick
import QtQuick.Effects
import "Util.js" as Util
import "../lib/shape.js" as Shape
import qs.Commons as Commons // qmllint disable import
import "../lib/motion.js" as Motion

// The frame every thumbnail shares, big or small: a soft shadow, the content
// clipped to rounded corners, and a thin ring drawn above the content, so
// nothing inside can spill over the outline. The overview cards and the
// workspace thumbnails are both built on it, so they look like one family.
//
// Colours come from the theme, the way Omarchy's own image picker does it: the
// accent for the selected one, a faint rim for the others.
//
//   ThumbFrame {
//       radius: shape.zone        // from lib/shape.js; the card size when left out
//       emphasized: selected       // the selection: accent ring, deeper shadow
//       current: viewed            // the one being looked at, while another thing has focus: soft accent ring
//       fill: "#22000000"          // behind the content
//       Image { anchors.fill: parent; ... }   // children are the content
//   }
Item {
    id: frame

    // The windows' real border width (-1: not known), which the rings follow (lib/shape.js).
    property int borderWidth: -1
    readonly property var ring: Shape.ring(frame.borderWidth)

    // From the windows' own rounding (lib/shape.js); a frame says which of the shapes it is.
    property real radius: Shape.radii(Commons.Style.cornerRadius).card
    property bool emphasized: false
    property bool current: false
    property color fill: "transparent"
    // 0..1: how far the frame has come off the desktop (the shadow and the ring grow
    // with it, so at 0 it is just the content).
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
        color: Qt.rgba(0, 0, 0, (frame.emphasized ? Shape.ALPHA.shadowStrong : Shape.ALPHA.shadow) * frame.depth)
        Behavior on color { ColorAnimation { duration: Commons.Style.duration(Motion.TOKENS.dur.fade) } }
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

    // The mask has to be an invisible item with a layer. It is a pixel smaller than the
    // frame on every side: the mask's edge is soft, so a mask as big as the frame lets
    // the content show a pixel beyond the corner of the ring, which a light picture on a
    // light theme makes plain. The ring, drawn above, covers that pixel. (On a frame that
    // has not come off the desktop, `depth` 0, there is no ring and no inset.)
    Item {
        id: roundedMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            anchors.margins: frame.depth
            radius: Math.max(0, frame.radius - frame.depth)
            color: "black"
        }
    }

    // The ring: the accent when selected, a softer accent for the workspace being
    // looked at, a faint rim otherwise.
    Rectangle {
        anchors.fill: parent
        radius: frame.radius
        color: "transparent"
        opacity: frame.depth
        border.width: frame.emphasized || frame.current ? frame.ring.strong : frame.ring.rim
        border.color: frame.emphasized ? frame.accent
            : (frame.current ? Util.withAlpha(frame.accent, Shape.ALPHA.soft) : frame.rim)
        Behavior on border.color { ColorAnimation { duration: Commons.Style.duration(Motion.TOKENS.dur.fade) } }
    }
}
