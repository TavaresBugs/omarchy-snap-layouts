import QtQuick
import QtQuick.Effects
import "Util.js" as Util
import qs.Commons as Commons // qmllint disable import

// The frame every thumbnail shares, big or small: a soft shadow, the content
// clipped to rounded corners, and a thin neutral ring drawn above the content,
// so nothing inside can spill over the outline. The overview cards and the
// workspace thumbnails are both built on it, so they look like one family.
//
//   ThumbFrame {
//       radius: 10
//       emphasized: selected       // stronger ring and shadow
//       fill: "#22000000"          // behind the content
//       Image { anchors.fill: parent; ... }   // children are the content
//   }
Item {
    id: frame

    property int radius: 10
    property bool emphasized: false
    property color fill: "transparent"
    // Children declared inside a ThumbFrame go into the clipped area.
    default property alias content: clip.data

    // Soft shadow, deeper when emphasized.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Math.max(1, Math.round(frame.radius * 0.2))
        anchors.topMargin: Math.max(1, Math.round(frame.radius * 0.3))
        anchors.bottomMargin: -Math.round(frame.radius * 0.9)
        radius: frame.radius + 4
        color: "black"
        opacity: frame.emphasized ? 0.5 : 0.3
        Behavior on opacity { NumberAnimation { duration: 140 } }
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

    // Quiet ring: a faint rim always, a firmer one when emphasized.
    Rectangle {
        anchors.fill: parent
        radius: frame.radius
        color: "transparent"
        border.width: frame.emphasized ? 2 : 1
        border.color: Util.withAlpha(Commons.Color.popups.text, frame.emphasized ? 0.9 : 0.14)
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }
}
