import QtQuick
import Quickshell
import Quickshell.Hyprland

// The pointer while a window is dragged. It starts lua/drag.lua inside Hyprland on a
// button press and stops it on the release, and turns what that sends back (the window
// being dragged and where the pointer is) into a signal. It decides nothing: what the
// pointer is asking for is lib/drag.js, and what is drawn is the overlay's.
//
// Nothing here polls. `hyprctl` runs twice per drag (start, stop); every sample in
// between is an event from Hyprland, sent only when the position changes.
Item {
    id: root

    // The plugin's folder, where lua/drag.lua is.
    property string pluginDir: ""

    // Between start() and stop(), or until the sensor gave up (a click, or a lost release).
    property bool active: false

    // A window is being dragged and the pointer is at x, y (global logical pixels).
    signal sample(real x, real y, string address)
    // Nothing moved after the press (a click), or the release never came: the sensor stopped.
    signal gaveUp()

    readonly property string prefix: "io.github.n0rthstar88.snap-layouts:drag:"
    readonly property string file: JSON.stringify(root.pluginDir + "/lua/drag.lua")

    function start() {
        root.active = true;
        // `dofile` every time: the file is idempotent, and an updated one takes effect
        // without a reload.
        Quickshell.execDetached(["hyprctl", "eval", "dofile(" + root.file + "); snap_layouts.drag.start()"]);
    }

    function stop() {
        if (!root.active)
            return;
        root.active = false;
        Quickshell.execDetached(["hyprctl", "eval", "if snap_layouts and snap_layouts.drag then snap_layouts.drag.stop() end"]);
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!root.active || !event || event.name !== "custom" || String(event.data).indexOf(root.prefix) !== 0)
                return;
            var body = String(event.data).substring(root.prefix.length);
            if (body === "idle") {
                root.active = false;
                root.gaveUp();
                return;
            }
            // ADDRESS,X,Y
            var parts = body.split(",");
            if (parts.length === 3)
                root.sample(Number(parts[1]), Number(parts[2]), parts[0]);
        }
    }
}
