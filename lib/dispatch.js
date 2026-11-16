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
// arguments are not valid.
function moveToWorkspace(address, workspaceId, monitorName) {
    var id = Number(workspaceId);
    if (!validAddress(address) || !(id > 0) || Math.floor(id) !== id)
        return "";
    var move = "hl.dispatch(hl.dsp.window.move({ workspace = '" + id + "', follow = false, window = 'address:" + address + "' }))";
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
