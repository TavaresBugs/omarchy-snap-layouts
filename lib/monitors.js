.pragma library

// Monitor helpers. Hyprland reports pixels and a scale; everything else works in
// logical pixels, so a monitor is converted once here.

// Convert one entry of `hyprctl -j monitors` into
// { name, x, y, w, h, reserved: [l, t, r, b], workspaceId } in logical pixels.
function fromIpc(m) {
    var scale = Number(m.scale) || 1;
    var rotated = Number(m.transform) % 2 === 1;
    return {
        name: String(m.name),
        x: Number(m.x),
        y: Number(m.y),
        w: (rotated ? m.height : m.width) / scale,
        h: (rotated ? m.width : m.height) / scale,
        reserved: m.reserved && m.reserved.length === 4 ? m.reserved : [0, 0, 0, 0],
        workspaceId: m.activeWorkspace ? Number(m.activeWorkspace.id) : 1
    };
}

// The monitor (already converted) containing the global point, or null.
function at(monitors, x, y) {
    for (var i = 0; i < monitors.length; i++) {
        var m = monitors[i];
        if (x >= m.x && x < m.x + m.w && y >= m.y && y < m.y + m.h)
            return m;
    }
    return null;
}

// Find a monitor by Hyprland's numeric id in the raw ipc list; returns it converted.
function byId(ipcMonitors, id) {
    for (var i = 0; i < ipcMonitors.length; i++)
        if (Number(ipcMonitors[i].id) === Number(id))
            return fromIpc(ipcMonitors[i]);
    return null;
}
