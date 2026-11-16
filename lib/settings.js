.pragma library

// User options, read from this plugin's entry in ~/.config/omarchy/shell.json:
//
//   { "id": "io.github.n0rthstar88.snap-layouts",
//     "dragToSnap": true,
//     "edgeSnap": true,           // snap by dragging against an edge or corner
//     "edgeDwellMs": 320,         // how long to hold there before the preview shows
//     "edgeMargin": 12,           // px from the edge that count as "at the edge"
//     "edgeCorner": 90,           // px along an edge that count as a corner
//     "overviewScope": "workspace" }   // "workspace" or "all"
//
// Anything missing or invalid falls back to the default, so a typo in the file
// can never break the plugin.

var DEFAULTS = {
    edgeSnap: true,
    edgeDwellMs: 320,
    edgeMargin: 12,
    edgeCorner: 90,
    overviewScope: "workspace"
};

var LIMITS = {
    edgeDwellMs: [0, 3000],
    edgeMargin: [1, 80],
    edgeCorner: [10, 400]
};

var SCOPES = ["workspace", "all"];

function number(value, key) {
    var n = Number(value);
    if (typeof value !== "number" || !isFinite(n))
        return DEFAULTS[key];
    return Math.max(LIMITS[key][0], Math.min(LIMITS[key][1], n));
}

// Turn a raw plugin entry (or null) into complete, validated options.
// dragToSnap keeps its own tri-state handling elsewhere (unset means "ask").
function resolve(entry) {
    var e = entry || {};
    return {
        edgeSnap: typeof e.edgeSnap === "boolean" ? e.edgeSnap : DEFAULTS.edgeSnap,
        edgeDwellMs: number(e.edgeDwellMs, "edgeDwellMs"),
        edgeMargin: number(e.edgeMargin, "edgeMargin"),
        edgeCorner: number(e.edgeCorner, "edgeCorner"),
        overviewScope: SCOPES.indexOf(e.overviewScope) >= 0 ? e.overviewScope : DEFAULTS.overviewScope
    };
}
