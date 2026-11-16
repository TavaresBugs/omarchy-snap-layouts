.pragma library

// The workspace modes behind Super+L. Omarchy cycles a workspace through tiling
// ("dwindle"), scrolling and floating. The plugin adds a fourth, "mosaic"
// (WinSaico), and builds it the way the layout picker (Super+Z) places windows: the
// workspace stays in Omarchy's tiling layout and the plugin floats the windows
// itself. Omarchy's own floating mode is not used: it floats every window that opens
// there at a set size (a menu or a popup too), gives each a title bar and takes over
// focus. A WinSaico workspace has none of that; its windows are free to move, resize
// and overlap, and with auto-fit on (lib/autosnap.js) they share the screen in the
// plugin's layouts. A workspace is in mosaic mode when Omarchy has it in tiling AND
// the plugin has it in its own list (or WinSaico is the default layout and the
// workspace was not set to plain tiling on purpose), so Omarchy never needs to know
// the mode exists and, with the plugin off, Super+L is Omarchy's three modes untouched.
//
// Pure decisions, no Qt objects.

// The order Super+L walks, and Super+Alt+L walks back.
var RING = ["dwindle", "scrolling", "floating", "mosaic"];

// What the bar calls each mode.
var LABELS = { dwindle: "tiling", scrolling: "scrolling", floating: "floating", mosaic: "winsaico" };

// Omarchy's own three, in the order its layout key cycles them.
var NATIVE = ["dwindle", "scrolling", "floating"];

// Is this workspace one of the plugin's WinSaico workspaces? Either it is in the
// plugin's list, or WinSaico is the default layout and the workspace was not set
// to plain tiling on purpose (`plain`, the list of those). `defaults` is
// { defaultMosaic, plain }.
function isMosaic(mosaicWorkspaces, workspace, defaults) {
    var n = Number(workspace);
    if ((mosaicWorkspaces || []).indexOf(n) !== -1)
        return true;
    var d = defaults || {};
    return d.defaultMosaic === true && (d.plain || []).indexOf(n) === -1;
}

// The mode a workspace is in, from what Omarchy reports for it and the plugin's
// list of mosaic workspaces (and, when WinSaico is the default layout, the
// workspaces set to plain tiling). Anything unrecognised counts as tiling, which is
// what Omarchy falls back to.
function current(omarchyMode, mosaicWorkspaces, workspace, defaults) {
    var mode = NATIVE.indexOf(String(omarchyMode)) >= 0 ? String(omarchyMode) : "dwindle";
    if (mode === "dwindle" && isMosaic(mosaicWorkspaces, workspace, defaults))
        return "mosaic";
    return mode;
}

// The next mode around the ring: direction "next" or "back".
function neighbour(mode, direction) {
    var i = RING.indexOf(mode);
    if (i < 0)
        i = 0;
    var step = direction === "back" ? RING.length - 1 : 1;
    return RING[(i + step) % RING.length];
}

// The one press of Omarchy's layout key ("next" or "back") that takes a workspace
// from one of its three modes to another, or "" when there is nothing to press.
function omarchyStep(from, to) {
    var a = NATIVE.indexOf(String(from)), b = NATIVE.indexOf(String(to));
    if (a < 0 || b < 0 || a === b)
        return "";
    return (a + 1) % 3 === b ? "next" : "back";
}

// What it takes to put a workspace in `target` (one of RING), coming from `from`
// (the mode it is in now, one of RING; leave it out when it does not matter):
//   { target, step, listed, plain, notify, release }
// - step: the press of Omarchy's layout key to make, or "" for none. WinSaico sits on
//   Omarchy's tiling, so reaching it from scrolling or floating is a step to tiling
//   (made silently, since Omarchy's own message would say tiling);
// - listed: whether the workspace ends up in the plugin's list;
// - plain: whether it ends up on the list of workspaces set to plain tiling, which
//   keeps WinSaico as the default layout from taking it over again;
// - notify: whether the plugin must say the new mode itself. Omarchy's script
//   announces the modes it sets, but not WinSaico, and says nothing when it is not
//   pressed;
// - release: what to do with the windows the plugin floated when leaving WinSaico:
//   "tile" gives them back to the tiling (the next mode is tiling or scrolling),
//   "claim" hands them to Omarchy's floating mode, which tiles them when it ends.
// Null when `target` is not a mode.
function plan(omarchyMode, target, from) {
    if (RING.indexOf(target) < 0)
        return null;
    var underneath = target === "mosaic" ? "dwindle" : target;
    var step = omarchyStep(NATIVE.indexOf(String(omarchyMode)) >= 0 ? omarchyMode : "dwindle", underneath);
    var release = "";
    if (from === "mosaic" && target !== "mosaic")
        release = target === "floating" ? "claim" : "tile";
    return { target: target, step: step, listed: target === "mosaic", plain: target === "dwindle", notify: step === "" || target === "mosaic", release: release };
}

// The workspace numbers in the plugin's state file (one per line); anything that is
// not a whole number above zero is ignored.
function parseList(text) {
    var seen = {}, out = [];
    String(text || "").split("\n").forEach(function(line) {
        var t = line.trim();
        if (!/^[0-9]+$/.test(t))
            return;
        var n = Number(t);
        if (n > 0 && !seen[n]) {
            seen[n] = true;
            out.push(n);
        }
    });
    return out.sort(function(a, b) { return a - b; });
}
