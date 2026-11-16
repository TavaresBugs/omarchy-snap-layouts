.pragma library

// hyprctl is asked for several things in one go (monitors, clients, workspaces, ...), each
// answer separated by this line, so one process gathers them all.
var SEPARATOR = "\n@@SNAP@@\n";

// The answers, parsed; null for one that is not JSON.
function parseSections(text) {
    var parts = String(text).split(SEPARATOR);
    var out = [];
    for (var i = 0; i < parts.length; i++) {
        try {
            out.push(JSON.parse(parts[i]));
        } catch (e) {
            out.push(null);
        }
    }
    return out;
}
