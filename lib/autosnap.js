.pragma library
.import "layouts.js" as Layouts
.import "windows.js" as Windows

// Auto-fit: on a WinSaico workspace with auto-fit on, the windows share the
// screen in the plugin's mosaic (lib/layouts.js `mosaicZones`): one fills the
// usable area, two share it, three make a half and two quarters, four make
// quarters, and more are dealt in even rows. They are floating windows, so
// everything is a size and a place; nothing here tiles. Pure decisions, no Qt
// objects: the plugin feeds in `hyprctl -j clients` and carries out what comes back.
//
// Who takes part. Every window of the workspace that has joined (the plugin
// remembers it placed them), that the plugin floated itself (it tags those
// `snap-layouts-floated`, which outlives a restart of the shell), or that is tiled
// there. A window that floats on its own account (a dialog, a popup,
// an app with a float rule) stays out, unless the mode has just been switched on
// (`adopt`), which brings everything in once. Fullscreen and pinned windows are
// never touched.
//
// The oldest window takes the first zone and a new one goes last, so a window
// keeps its place in the mosaic as others come and go.

// How close a window must be to its target for the plugin to leave it alone.
var IN_PLACE_TOLERANCE = 2;

var CLAIMED_TAGS = ["snap-layouts-floated"];

function claimed(c) {
    return (c.tags || []).some(function(t) {
        return CLAIMED_TAGS.indexOf(String(t).replace("*", "")) >= 0;
    });
}

function near(a, b) {
    return Math.abs(Number(a) - Number(b)) <= IN_PLACE_TOLERANCE;
}

function isManaged(c, record, adopt) {
    if (!c || Number(c.fullscreen) > 0 || c.pinned)
        return false;
    return !!record || claimed(c) || c.floating === false || adopt === true;
}

// Where a window sits in the order the zones are handed out: the ones that joined
// by their sequence number, windows from before by how long ago they were used
// (oldest first), and the ones that just opened last (oldest of those first).
function orderKey(c, records, isNew) {
    var r = records[c.address];
    if (r)
        return r.seq;
    var recency = Number(c.focusHistoryID || 0);
    return isNew ? 1e9 - recency : -1e6 - recency;
}

// What to do for one workspace. `input`:
//   monitor       the workspace's monitor, as built by monitors.js
//   gaps          { outer, inner, border }
//   workspaceId   the workspace
//   clients       `hyprctl -j clients`
//   records       { address: { seq } } of the windows that have joined
//   newAddresses  the windows that just opened (or arrived), if any
//   adopt         true right after the mode was switched on: floating windows join too
//   nextSeq       the next free sequence number
// Returns { items, nextSeq }, items in zone order:
//   { address, zone, at: [x, y], size: [w, h], seq, float, move }
// `move` is false for a window already where it belongs; `float` says it is still
// tiled and has to be floated first.
function plan(input) {
    var records = input.records || {};
    var fresh = input.newAddresses || [];
    var managed = (input.clients || []).filter(function(c) {
        return Windows.isSnappable(c)
            && Number(c.workspace.id) === Number(input.workspaceId)
            && isManaged(c, records[c.address], input.adopt === true);
    });
    var keyed = managed.map(function(c) {
        return { c: c, key: orderKey(c, records, fresh.indexOf(c.address) >= 0) };
    });
    keyed.sort(function(a, b) {
        return a.key < b.key ? -1 : a.key > b.key ? 1 : 0;
    });

    var zones = Layouts.mosaicZones(keyed.length);
    var seq = Number(input.nextSeq) || 1;
    var items = [];
    for (var i = 0; i < keyed.length; i++) {
        var c = keyed[i].c;
        var r = Layouts.zoneRect(input.monitor, input.gaps, zones[i]);
        var at = [r.x, r.y];
        var size = [r.w, r.h];
        var recorded = records[c.address];
        var inPlace = c.floating === true
            && near(c.at[0], at[0]) && near(c.at[1], at[1])
            && near(c.size[0], size[0]) && near(c.size[1], size[1]);
        items.push({
            address: c.address,
            zone: i,
            at: at,
            size: size,
            seq: recorded ? recorded.seq : seq++,
            float: c.floating !== true,
            move: !inPlace
        });
    }
    return { items: items, nextSeq: seq };
}

// With auto-fit off, a workspace that joins WinSaico floats its tiled windows where
// they are, so nothing jumps: items like plan()'s, for the tiled windows only. Windows
// that float on their own account, fullscreen and pinned ones are left alone.
function keep(workspaceId, clients) {
    return (clients || []).filter(function(c) {
        return Windows.isSnappable(c)
            && Number(c.workspace.id) === Number(workspaceId)
            && c.floating === false
            && !(Number(c.fullscreen) > 0) && !c.pinned;
    }).map(function(c, i) {
        return { address: c.address, zone: i, at: [c.at[0], c.at[1]], size: [c.size[0], c.size[1]], seq: 0, float: true, move: true };
    });
}
