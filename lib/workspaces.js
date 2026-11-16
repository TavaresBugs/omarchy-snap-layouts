.pragma library

// The workspace strip of the overview. Omarchy gives every monitor its own block
// of ten workspaces (monitor 1: 1-10, monitor 2: 11-20, ...) and the bar shows
// the first five of the block plus any later ones that exist, labelled by their
// position in the block. The strip follows the same rule for the monitor being
// looked at, and draws each workspace as the windows it holds.
//
// Pure functions, no Qt objects.

var SLOTS = 10;        // workspaces per monitor block
var VISIBLE = 5;       // always shown, even when empty

function blockOf(id) {
    return Math.floor((id - 1) / SLOTS);
}

// Position inside the block: 1..10.
function slotOf(id) {
    return (id - 1) % SLOTS + 1;
}

// Label as the bar writes it: 1..9, and 0 for the tenth.
function labelOf(id) {
    var slot = slotOf(id);
    return slot === SLOTS ? "0" : String(slot);
}

function clamp01(v) {
    return Math.max(0, Math.min(1, v));
}

// A window's outline as fractions (0..1) of its monitor.
function outline(client, monitor) {
    var x0 = clamp01((client.at[0] - monitor.x) / monitor.w);
    var y0 = clamp01((client.at[1] - monitor.y) / monitor.h);
    var x1 = clamp01((client.at[0] + client.size[0] - monitor.x) / monitor.w);
    var y1 = clamp01((client.at[1] + client.size[1] - monitor.y) / monitor.h);
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0, address: client.address };
}

// Entries for the strip, left to right.
//   clients:   `hyprctl -j clients` entries worth showing
//   monitors:  converted monitors (monitors.js) keyed by Hyprland monitor id
//   currentId: the workspace being looked at; its block is the one shown
// Each entry: { id, slot, label, windows: [{x, y, w, h, address}], count }, with
// windows ordered oldest focus first so the latest is drawn on top.
// Minimized windows (negative workspace ids) belong to no thumbnail.
function buildStrip(clients, monitors, currentId) {
    var block = blockOf(currentId);
    var base = block * SLOTS;
    var byId = {};

    clients.slice().sort(function(a, b) {
        return Number(b.focusHistoryID) - Number(a.focusHistoryID);
    }).forEach(function(c) {
        var id = Number(c.workspace && c.workspace.id);
        var m = monitors[c.monitor];
        if (!(id > 0) || blockOf(id) !== block || !m)
            return;
        (byId[id] = byId[id] || []).push(outline(c, m));
    });

    var ids = [];
    for (var s = 1; s <= SLOTS; s++) {
        var id = base + s;
        if (s <= VISIBLE || byId[id] || id === currentId)
            ids.push(id);
    }
    return ids.map(function(id) {
        var windows = byId[id] || [];
        return { id: id, slot: slotOf(id), label: labelOf(id), windows: windows, count: windows.length };
    });
}

// The workspace one step to the left (-1) or right (+1) of currentId in the
// strip, wrapping around.
function stepWorkspace(entries, currentId, delta) {
    if (entries.length === 0)
        return currentId;
    var ids = entries.map(function(e) { return e.id; });
    var at = ids.indexOf(currentId);
    if (at === -1)
        return ids[0];
    return ids[((at + delta) % ids.length + ids.length) % ids.length];
}
