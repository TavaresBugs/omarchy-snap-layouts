.pragma library

// Decisions about Hyprland windows (the entries of `hyprctl -j clients`): which
// ones the plugin offers, in what order, and which floating ones cover a tiled
// window. Pure functions, no Qt objects.

var MINIMIZED_WORKSPACE = "special:minimized";

// Windows the plugin can offer: mapped, visible, on a normal workspace or minimized.
function isSnappable(c) {
    if (!c || !c.address || c.mapped === false || c.hidden === true)
        return false;
    var ws = c.workspace || {};
    return Number(ws.id) > 0 || String(ws.name || "") === MINIMIZED_WORKSPACE;
}

// Windows that belong to a workspace: the ones on it, plus the ones minimized
// from it (Omarchy tags a minimized window with the workspace it came from).
function belongsToWorkspace(c, workspaceId) {
    var ws = c.workspace || {};
    if (Number(ws.id) === Number(workspaceId))
        return true;
    if (String(ws.name || "") !== MINIMIZED_WORKSPACE)
        return false;
    var tag = "omarchy-minimized-from-" + workspaceId;
    return (c.tags || []).some(function(t) { return String(t).replace("*", "") === tag; });
}

function recency(a, b) {
    return Number(a.focusHistoryID) - Number(b.focusHistoryID);
}

// Snap assist: only the windows of the workspace being filled (what the user
// can see there, plus the ones minimized from it), most recently used first.
function forAssist(list, workspaceId) {
    return list.filter(function(c) {
        return belongsToWorkspace(c, workspaceId);
    }).sort(recency);
}

// Overview: by workspace number (minimized ones last), then most recently used.
function sortForOverview(list) {
    function rank(c) {
        return Number(c.workspace.id) > 0 ? Number(c.workspace.id) : 1000;
    }
    return list.slice().sort(function(a, b) {
        return rank(a) !== rank(b) ? rank(a) - rank(b) : recency(a, b);
    });
}

// Alt+Tab style: start on the window used just before the current one
// (focus history 1). Falls back to the first window.
function previousWindowIndex(list) {
    var start = 0, best = Infinity;
    for (var i = 0; i < list.length; i++) {
        var h = Number(list[i].focusHistoryID);
        if (h > 0 && h < best) {
            best = h;
            start = i;
        }
    }
    return start;
}

// Positions and sizes keyed by address, to notice which window moves during a drag.
function positionsOf(list) {
    var map = {};
    for (var i = 0; i < (list || []).length; i++)
        map[list[i].address] = { at: list[i].at, size: list[i].size };
    return map;
}

function overlaps(a, b) {
    return a.at[0] < b.at[0] + b.size[0] && a.at[0] + a.size[0] > b.at[0]
        && a.at[1] < b.at[1] + b.size[1] && a.at[1] + a.size[1] > b.at[1];
}

// A tiled window can never be drawn above floating ones. These are the floating
// windows on its workspace that sit over it, which can be tiled so that all of
// them are visible together. Pinned and fullscreen windows are left alone.
function floatsCovering(target, clients) {
    var out = [];
    if (!target || target.floating !== false || !target.workspace || Number(target.workspace.id) <= 0)
        return out;
    for (var i = 0; i < clients.length; i++) {
        var o = clients[i];
        if (o.address === target.address || !o.floating || o.pinned || Number(o.fullscreen) > 0)
            continue;
        if (!o.workspace || Number(o.workspace.id) !== Number(target.workspace.id))
            continue;
        if (overlaps(o, target))
            out.push(o.address);
    }
    return out;
}
