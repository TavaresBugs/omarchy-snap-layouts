.pragma library

// Lua snippets for `hyprctl eval`. Everything interpolated into them is
// validated here, so a odd value can never turn into code.

function validAddress(address) {
    return /^0x[0-9a-fA-F]+$/.test(String(address));
}

function validMonitor(name) {
    return /^[A-Za-z0-9._:-]+$/.test(String(name));
}

// Send a window to a workspace without following it. `monitorName` is the
// monitor that owns the workspace. A workspace that is empty does not exist
// yet, and Hyprland would create it on the window's own monitor; so it is
// created on the owner by showing it there for a moment, and the owner's
// previous workspace and the focused window are put back. Returns "" when the
// arguments are not valid. With `tile`, a floating window is tiled on arrival.
function moveToWorkspace(address, workspaceId, monitorName, tile) {
    var id = Number(workspaceId);
    if (!validAddress(address) || !(id > 0) || Math.floor(id) !== id)
        return "";
    var move = "hl.dispatch(hl.dsp.window.move({ workspace = '" + id + "', follow = false, window = 'address:" + address + "' }))";
    if (tile)
        move += " hl.dispatch(hl.dsp.window.float({ action = 'off', window = 'address:" + address + "' }))";
    if (!monitorName)
        return move;
    if (!validMonitor(monitorName))
        return "";
    return [
        "local mon = hl.get_monitor('" + monitorName + "')",
        "if hl.get_workspace(" + id + ") or not mon then " + move + " else",
        "local prev = mon.active_workspace and mon.active_workspace.id",
        "local active = hl.get_active_window()",
        "hl.dispatch(hl.dsp.focus({ monitor = mon.name }))",
        "hl.dispatch(hl.dsp.focus({ workspace = '" + id + "' }))",
        move,
        "if prev and hl.get_workspace(prev) then mon:set_workspace({ workspace = tostring(prev) })",
        "elseif prev then hl.dispatch(hl.dsp.focus({ workspace = tostring(prev) })) end",
        "if active then hl.dispatch(hl.dsp.focus({ window = 'address:' .. active.address })) end",
        "end"
    ].join(" ");
}

// Make two workspaces trade places: each keeps its windows and takes the
// other's number. A workspace that does not exist yet is just renumbered
// into. Hyprland needs a free number in between, hence the third step.
function swapWorkspaces(a, b) {
    var x = Number(a), y = Number(b);
    if (!(x > 0) || !(y > 0) || Math.floor(x) !== x || Math.floor(y) !== y || x === y)
        return "";
    var tmp = 100000 + x;
    function renumber(from, to) {
        return "hl.dispatch(hl.dsp.workspace.change_id({ workspace = '" + from + "', id = " + to + " }))";
    }
    return [
        "local a, b = hl.get_workspace(" + x + "), hl.get_workspace(" + y + ")",
        "if a and b then " + renumber(x, tmp) + " " + renumber(y, x) + " " + renumber(tmp, y),
        "elseif a then " + renumber(x, y),
        "elseif b then " + renumber(y, x) + " end"
    ].join(" ");
}

// Go to a workspace of the monitor that owns it, the way Omarchy's own keys do
// (its slot on that monitor). Without the owner, plain focus.
function goToWorkspace(workspaceId, slot, monitorName) {
    var id = Number(workspaceId), s = Number(slot);
    if (!(id > 0) || Math.floor(id) !== id)
        return "";
    var plain = "hl.dispatch(hl.dsp.focus({ workspace = '" + id + "' }))";
    if (!monitorName || !(s > 0) || !validMonitor(monitorName))
        return plain;
    return "if o and o.workspaces then hl.dispatch(o.workspaces.focus(" + s + ", '" + monitorName + "')) else " + plain + " end";
}
