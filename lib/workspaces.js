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

// The part of a monitor windows can use: what the bar and docks leave free,
// less the gap to the screen edge. Thumbnails show this, not the whole panel,
// so tiled windows fill them the way they fill the screen.
function usableArea(monitor, inset) {
    var r = monitor.reserved || [0, 0, 0, 0];
    var g = inset || 0;
    return {
        x: monitor.x + r[0] + g,
        y: monitor.y + r[1] + g,
        w: Math.max(1, monitor.w - r[0] - r[2] - 2 * g),
        h: Math.max(1, monitor.h - r[1] - r[3] - 2 * g)
    };
}

// A window's outline as fractions (0..1) of the usable area of its monitor.
function outline(client, monitor, inset) {
    var a = usableArea(monitor, inset);
    var x0 = clamp01((client.at[0] - a.x) / a.w);
    var y0 = clamp01((client.at[1] - a.y) / a.h);
    var x1 = clamp01((client.at[0] + client.size[0] - a.x) / a.w);
    var y1 = clamp01((client.at[1] + client.size[1] - a.y) / a.h);
    return {
        x: x0, y: y0, w: x1 - x0, h: y1 - y0, address: client.address,
        floating: !!client.floating,
        // Windows of an Omarchy floating workspace: nothing is tiled there.
        floatSpace: (client.tags || []).some(function(t) { return String(t).replace("*", "") === "omarchy-floating-workspace"; })
    };
}

// Entries for the strip, left to right.
//   clients:   `hyprctl -j clients` entries worth showing
//   monitors:  converted monitors (monitors.js) keyed by Hyprland monitor id
//   currentId: the workspace being looked at; its block is the one shown
// Each entry: { id, slot, label, windows: [{x, y, w, h, address, floating, floatSpace}], count }, with
// windows ordered oldest focus first so the latest is drawn on top.
// Minimized windows (negative workspace ids) belong to no thumbnail.
//   viewedId:  optional, a workspace of the block to show even if it is empty
//   inset:     optional, the gap to the screen edge, left out of the usable area
function buildStrip(clients, monitors, currentId, viewedId, inset) {
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
        (byId[id] = byId[id] || []).push(outline(c, m, inset));
    });

    var ids = [];
    for (var s = 1; s <= SLOTS; s++) {
        var id = base + s;
        if (s <= VISIBLE || byId[id] || id === currentId || id === viewedId)
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

// The monitor (converted, keyed by Hyprland id) that owns a workspace's block,
// judged by the workspace each monitor is showing. Null when none matches.
function monitorFor(id, monitorsById) {
    var block = blockOf(id);
    for (var key in monitorsById)
        if (blockOf(monitorsById[key].workspaceId) === block)
            return monitorsById[key];
    return null;
}

// A laptop's built-in panel (eDP, LVDS, DSI).
function isInternal(name) {
    return /^(eDP|LVDS|DSI)/.test(String(name));
}

// One strip per monitor, the main one first. The main monitor is the one named
// `mainName`; without a choice, an external monitor beats the laptop panel
// (docked, the external one is the one you work on), then the first block wins.
// The order never depends on which screen the overview is opened on.
// Each: { name, main, workspaceId, aspect (of the usable area), entries }; `workspaceId` is what the
// monitor is showing, `viewedId` the workspace the overview is looking at.
function screens(clients, monitorsById, viewedId, mainName, inset) {
    var list = Object.keys(monitorsById).map(function(key) { return monitorsById[key]; });
    list.sort(function(a, b) {
        if ((a.name === mainName) !== (b.name === mainName))
            return a.name === mainName ? -1 : 1;
        if (isInternal(a.name) !== isInternal(b.name))
            return isInternal(a.name) ? 1 : -1;
        return blockOf(a.workspaceId) - blockOf(b.workspaceId) || a.id - b.id;
    });
    return list.map(function(m, i) {
        var area = usableArea(m, inset);
        return {
            name: m.name,
            main: i === 0,
            workspaceId: m.workspaceId,
            aspect: area.w / area.h,
            entries: buildStrip(clients, monitorsById, m.workspaceId, viewedId, inset)
        };
    });
}

// The entries of the strip that holds a workspace (the first strip if none does).
function entriesFor(strips, id) {
    for (var i = 0; i < strips.length; i++)
        for (var j = 0; j < strips[i].entries.length; j++)
            if (strips[i].entries[j].id === id)
                return strips[i].entries;
    return strips.length > 0 ? strips[0].entries : [];
}

// What dropping `client` (a `hyprctl clients` entry) onto a strip entry looks
// like. A tiled window joins the layout by splitting the most recently used
// tiled window along its longer side; the same is done for a floating window
// that is tiled on arrival. `aspect` is the monitor's width over height.
// Returns { windows, slot, tile }: the outlines after the drop, the new
// window's slot (null when it stays floating) and whether it will be tiled.
function dropPreview(entry, client, aspect) {
    var others = entry.windows.filter(function(w) { return w.address !== client.address; });
    var tile = !client.floating
        || (!client.pinned
            && others.some(function(w) { return !w.floating; })
            && !others.some(function(w) { return w.floatSpace; }));
    if (!tile)
        return { windows: others, slot: null, tile: false };

    var tiled = others.filter(function(w) { return !w.floating; });
    if (tiled.length === 0)
        return { windows: others, slot: { x: 0, y: 0, w: 1, h: 1 }, tile: true };

    var target = tiled[tiled.length - 1];     // oldest first, so the last is the latest
    var wide = target.w * aspect >= target.h;
    var kept = wide
        ? { x: target.x, y: target.y, w: target.w / 2, h: target.h }
        : { x: target.x, y: target.y, w: target.w, h: target.h / 2 };
    var slot = wide
        ? { x: target.x + target.w / 2, y: target.y, w: target.w / 2, h: target.h }
        : { x: target.x, y: target.y + target.h / 2, w: target.w, h: target.h / 2 };
    return {
        windows: others.map(function(w) {
            return w === target ? Object.assign({}, w, kept) : w;
        }),
        slot: slot,
        tile: true
    };
}

// Which way the view moves when going from one workspace to another: 1 when the
// target is further along the strips (main first, left to right), -1 when
// before, 0 when either is unknown.
function direction(strips, fromId, toId) {
    var order = [];
    strips.forEach(function(s) {
        s.entries.forEach(function(e) { order.push(e.id); });
    });
    var a = order.indexOf(fromId), b = order.indexOf(toId);
    return a < 0 || b < 0 || a === b ? 0 : (b > a ? 1 : -1);
}
