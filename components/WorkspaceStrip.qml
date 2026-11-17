pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons // qmllint disable import
import qs.Commons as Commons // qmllint disable import
import "Util.js" as Util
import "../lib/shape.js" as Shape
import "../lib/motion.js" as Motion

// A row of workspace thumbnails. Each one shows what the workspace really holds:
// its windows, drawn small at their real positions with their live picture.
// Empty workspaces are dimmed. The selected one gets a thin neutral ring.
// Presentation only: it reports clicks as a signal.
//
//   entries: from Workspaces.buildStrip -> [{ id, label, windows: [{x, y, w, h, address}], count }]
Item {
    id: strip

    // Every corner comes from lib/shape.js, from the windows' own rounding.
    readonly property var shape: Shape.radii(Style.cornerRadius)
    property int borderWidth: -1
    readonly property var ring: Shape.ring(strip.borderWidth)

    property var entries: []
    property int selectedId: 0
    property real aspect: 16 / 9
    property int thumbHeight: 76
    property var toplevelFor: function(address) { return null; }
    // A window is being dragged over this workspace (or -1): it lights up as a drop target.
    property int dropId: -1
    // What the drop would look like: { windows, slot } from Workspaces.dropPreview,
    // and the picture of the window being dropped, shown in its slot.
    property var drop: null
    property var dropToplevel: null
    // The keyboard is on the strip: the viewed workspace stands out a little more.
    property bool focused: false

    signal chosen(var entry)           // click: look at this workspace
    signal activated(var entry)        // double click: go to it
    signal reorderRequested(int from, int to)    // a thumbnail was dragged onto another

    // Reordering: the thumbnail being dragged, how far, and the one under it.
    property int dragId: -1
    property real dragDx: 0
    property real dragDy: 0
    property int overId: -1

    // The workspace under a point given in this strip's coordinates, or -1.
    // `skipId` leaves one thumbnail out (the one being dragged).
    function idAt(px, py, skipId) {
        for (var i = 0; i < repeater.count; i++) {
            var thumb = repeater.itemAt(i);
            if (thumb.modelData.id === skipId)
                continue;
            var p = thumb.mapFromItem(strip, px, py);
            if (p.x >= 0 && p.y >= 0 && p.x <= thumb.width && p.y <= thumb.height)
                return thumb.modelData.id;
        }
        return -1;
    }

    implicitWidth: row.implicitWidth
    implicitHeight: thumbHeight

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12

        Repeater {
            id: repeater
            model: strip.entries

            Item {
                id: thumb
                required property var modelData
                readonly property bool selected: modelData.id === strip.selectedId
                readonly property bool empty: modelData.count === 0
                readonly property bool target: modelData.id === strip.dropId
                readonly property bool previewing: target && strip.drop !== null
                readonly property bool dragging: strip.dragId === modelData.id
                readonly property bool over: strip.overId === modelData.id

                // Where a window sits: after the drop, if this is the target.
                function frameOf(w) {
                    if (previewing)
                        for (var i = 0; i < strip.drop.windows.length; i++)
                            if (strip.drop.windows[i].address === w.address)
                                return strip.drop.windows[i];
                    return w;
                }

                width: Math.round(strip.thumbHeight * strip.aspect)
                height: strip.thumbHeight
                scale: (selected && strip.focused) ? 1.1 : (selected || target || over || dragging || mouse.containsMouse ? 1.05 : 1)
                opacity: dragging ? 0.9 : (selected || target || over || mouse.containsMouse ? 1 : (empty ? 0.55 : 0.88))
                z: dragging ? 50 : 0
                transform: Translate {
                    x: thumb.dragging ? strip.dragDx : 0
                    y: thumb.dragging ? strip.dragDy : 0
                }
                Behavior on scale { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.quick); easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.quick) } }

                ThumbFrame {
                    anchors.fill: parent
                    radius: strip.shape.thumb
                    borderWidth: strip.borderWidth
                    // Strong where the focus is: the viewed workspace when the strip has it,
                    // or a drop target; the viewed one is only softly marked otherwise.
                    emphasized: (thumb.selected && strip.focused) || thumb.target || thumb.over
                    current: thumb.selected && !strip.focused
                    fill: Util.withAlpha(Commons.Color.popups.background, Shape.ALPHA.pane)

                    // The windows, at their real positions, with their live picture.
                    Repeater {
                        model: thumb.modelData.windows

                        Item {
                            id: win
                            required property var modelData
                            readonly property var placed: thumb.frameOf(modelData)
                            x: placed.x * thumb.width
                            y: placed.y * thumb.height
                            width: Math.max(4, placed.w * thumb.width)
                            height: Math.max(4, placed.h * thumb.height)
                            Behavior on x { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.fade); easing.type: Easing.OutCubic } }
                            Behavior on y { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.fade); easing.type: Easing.OutCubic } }
                            Behavior on width { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.fade); easing.type: Easing.OutCubic } }
                            Behavior on height { NumberAnimation { duration: Style.duration(Motion.TOKENS.dur.fade); easing.type: Easing.OutCubic } }

                            WindowPicture {
                                anchors.fill: parent
                                toplevel: strip.toplevelFor(win.modelData.address)
                                cornerRadius: 0
                                backdrop: Util.withAlpha(Commons.Color.background, Shape.ALPHA.placeholder)
                                fallbackIconSize: 0
                            }
                            // A hairline keeps neighbouring windows apart.
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.width: strip.ring.rim
                                border.color: Util.withAlpha("black", Shape.ALPHA.edge)
                            }
                        }
                    }

                    // Where the dropped window will land: its slot, filled with its picture.
                    Item {
                        readonly property var rect: strip.drop ? strip.drop.slot : null
                        visible: thumb.previewing && rect !== null
                        x: (rect ? rect.x : 0) * thumb.width
                        y: (rect ? rect.y : 0) * thumb.height
                        width: Math.max(4, (rect ? rect.w : 0) * thumb.width)
                        height: Math.max(4, (rect ? rect.h : 0) * thumb.height)

                        WindowPicture {
                            anchors.fill: parent
                            toplevel: strip.dropToplevel
                            cornerRadius: 0
                            backdrop: Util.withAlpha(Commons.Color.popups.text, Shape.ALPHA.muted)
                            fallbackIconSize: 0
                            opacity: Shape.ALPHA.label
                        }
                        Rectangle {
                            anchors.fill: parent
                            color: Util.withAlpha(Commons.Color.imagePicker.selectedBorder, Shape.ALPHA.tintStrong)
                            border.color: Commons.Color.imagePicker.selectedBorder
                            border.width: strip.ring.strong
                        }
                    }

                    // Workspace number, as in the bar: plain text, no badge.
                    Text {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: Style.spacing.md
                        text: thumb.modelData.label
                        color: Commons.Color.popups.text
                        font.family: Qt.application.font.family
                        font.pixelSize: Style.font.body - 2
                        font.weight: Font.DemiBold
                        style: Text.Outline
                        styleColor: Util.withAlpha("black", Shape.ALPHA.outline)
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: thumb.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                    // A press that travels further than this is a drag, not a click.
                    readonly property int threshold: 8
                    property point pressAt
                    property bool moved: false

                    onPressed: function(m) {
                        pressAt = mapToItem(strip, m.x, m.y);
                        moved = false;
                    }
                    onPositionChanged: function(m) {
                        if (!pressed)
                            return;
                        var p = mapToItem(strip, m.x, m.y);
                        if (!moved && Math.hypot(p.x - pressAt.x, p.y - pressAt.y) > threshold) {
                            moved = true;
                            strip.dragId = thumb.modelData.id;
                        }
                        if (moved) {
                            strip.dragDx = p.x - pressAt.x;
                            strip.dragDy = p.y - pressAt.y;
                            strip.overId = strip.idAt(p.x, p.y, thumb.modelData.id);
                        }
                    }
                    onReleased: {
                        if (!moved)
                            return;
                        var from = thumb.modelData.id;
                        var to = strip.overId;
                        strip.dragId = -1;
                        strip.overId = -1;
                        strip.dragDx = 0;
                        strip.dragDy = 0;
                        if (to > 0)
                            strip.reorderRequested(from, to);
                    }
                    onClicked: {
                        if (!moved)
                            strip.chosen(thumb.modelData);
                    }
                    onDoubleClicked: {
                        if (!moved)
                            strip.activated(thumb.modelData);
                    }
                }
            }
        }
    }
}
