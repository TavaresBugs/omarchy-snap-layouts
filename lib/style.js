.pragma library

// The system's look, read from Hyprland instead of being written down here:
// the gap to the screen edge and the border width. Input is the JSON of `hyprctl -j getoption <name>`, as parsed objects
// (null when the call failed); anything unreadable falls back to a default, so
// a missing answer never breaks the plugin.

var FALLBACK = { outer: 2, border: 2 };

function number(v) {
    if (v === null || v === undefined || String(v).trim() === "")
        return null;
    var n = Number(v);
    return isFinite(n) && n >= 0 ? n : null;
}

// One value from a getoption reply: an int/float, or the first number of a
// CSS-style list ("2 2 2 2": top, right, bottom, left).
function read(reply) {
    if (!reply)
        return null;
    if (reply.int !== undefined)
        return number(reply.int);
    if (reply.float !== undefined)
        return number(reply.float);
    if (typeof reply.css === "string")
        return number(reply.css.trim().split(/\s+/)[0]);
    return null;
}

function pick(reply, fallback) {
    var v = read(reply);
    return v === null ? fallback : v;
}

// { outer, border } in logical pixels.
function resolve(gapsOut, borderSize) {
    return {
        outer: Math.round(pick(gapsOut, FALLBACK.outer)),
        border: Math.round(pick(borderSize, FALLBACK.border))
    };
}
