.pragma library

// The workspace strip of the overview: one small thumbnail per workspace that
// has windows (plus the current one and an empty slot for a new workspace), each
// drawn as its windows' outlines. Pure functions, no Qt objects.

var MAX_WORKSPACE = 10;

function clamp01(v) {
    return Math.max(0, Math.min(1, v));
}

// Outline of a window as fractions (0..1) of its monitor.
function outline(client, monitor) {
    var w = monitor.w, h = monitor.h;
    var x0 = clamp01((client.at[0] - monitor.x) / w);
    var y0 = clamp01((client.at[1] - monitor.y) / h);
    var x1 = clamp01((client.at[0] + client.size[0] - monitor.x) / w);
    var y1 = clamp01((client.at[1] + client.size[1] - monitor.y) / h);
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
}

// Smallest workspace number from 1 that nothing uses, or 0 when all are taken.
function nextFree(usedIds) {
    for (var n = 1; n <= MAX_WORKSPACE; n++)
        if (usedIds.indexOf(n) === -1)
            return n;
    return 0;
}

// Entries for the strip, left to right.
//   clients:   `hyprctl -j clients` entries (already limited to ones worth showing)
//   monitors:  converted monitors (monitors.js) keyed by Hyprland monitor id
//   currentId: the workspace being looked at, kept even when it is empty
// Each entry: { id, isNew, windows: [{x, y, w, h}] (fractions), count }.
// Minimized windows (negative workspace ids) are not part of any thumbnail.
function buildStrip(clients, monitors, currentId) {
    var byId = {};
    clients.forEach(function(c) {
        var id = Number(c.workspace && c.workspace.id);
        if (!(id > 0))
            return;
        var m = monitors[c.monitor];
        if (!m)
            return;
        (byId[id] = byId[id] || []).push(outline(c, m));
    });
    if (!byId[currentId])
        byId[currentId] = [];

    var ids = Object.keys(byId).map(Number).sort(function(a, b) { return a - b; });
    var entries = ids.map(function(id) {
        return { id: id, isNew: false, windows: byId[id], count: byId[id].length };
    });
    var free = nextFree(ids);
    if (free > 0)
        entries.push({ id: free, isNew: true, windows: [], count: 0 });
    return entries;
}

// The workspace one step to the left (-1) or right (+1) of currentId among the
// real ones (not the empty "new" slot), wrapping around.
function stepWorkspace(entries, currentId, delta) {
    var real = entries.filter(function(e) { return !e.isNew; }).map(function(e) { return e.id; });
    if (real.length === 0)
        return currentId;
    var at = real.indexOf(currentId);
    if (at === -1)
        return real[0];
    return real[((at + delta) % real.length + real.length) % real.length];
}
