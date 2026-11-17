.pragma library
.import "edge.js" as Edge
.import "monitors.js" as Monitors

// What the pointer is asking for while a window is dragged: the rules that turn a
// stream of positions into "show the edge preview", "open the picker" or "nothing".
// Pure functions, no Qt objects. Where the positions come from (the Hyprland side,
// lua/drag.lua) and what is drawn (the overlay) are somebody else's business.
//
// The pointer can ask for two things:
//   - a zone at an edge or a corner (lib/edge.js), after being held there for `dwellMs`:
//     the edge preview, which releasing turns into a snap;
//   - the layout picker, by going near the top of a screen.

function initial() {
    return { pending: "", since: 0 };
}

// One look at the pointer.
//   state:  what the last look left (start from initial())
//   sample: { x, y }  global logical pixels
//   ctx:    now        time of the look in ms
//           mode       what the overlay shows: "", "drag", "edge", "picker" or "assist"
//           current    name of the monitor the picker is on ("" when it is not open)
//           monitors   from lib/monitors.js
//           snapOn     is Snapping on
//           edge       { margin, corner }, as lib/edge.js reads them
//           dwellMs    how long to hold at an edge before its preview shows
//           topDistance how close to the top counts as asking for the picker
//
// Returns { state, act, ... }, where act is one of:
//   "none"            nothing to do
//   "edge-open"       show the edge preview: { monitor, edge } (edge: lib/edge.js's answer)
//   "edge-hover"      the preview is up and the pointer is still at an edge: { edge }
//   "edge-close"      the pointer left the edge: hide the preview
//   "picker-open"     open the picker on { monitor }
//   "picker-monitor"  the pointer went to another screen's top: move the picker to { monitor }
//   "picker-hover"    the picker is up: pick the zone under the pointer
// and `recheck`, when set, is the time in ms after which the same sample should be looked
// at again, because the answer changes by itself (the dwell running out).
function step(state, sample, ctx) {
    var next = { pending: state.pending, since: state.since };
    var monitor = Monitors.at(ctx.monitors, sample.x, sample.y);
    if (!monitor)
        return { state: next, act: "none" };

    var edge = ctx.snapOn ? Edge.edgeTarget(monitor, sample, ctx.edge) : null;
    var recheck = 0;
    if (edge) {
        if (ctx.mode === "edge")
            return { state: next, act: "edge-hover", edge: edge };
        if (next.pending !== edge.key) {
            next.pending = edge.key;
            next.since = ctx.now;
        }
        if (ctx.mode !== "picker" && ctx.mode !== "assist") {
            var waited = ctx.now - next.since;
            if (waited >= ctx.dwellMs)
                return { state: next, act: "edge-open", monitor: monitor, edge: edge };
            recheck = ctx.dwellMs - waited;
        }
    } else {
        next.pending = "";
        if (ctx.mode === "edge")
            return { state: next, act: "edge-close" };
    }

    var nearTop = sample.y - monitor.y <= ctx.topDistance;
    var act = "none";
    if (ctx.mode === "" && nearTop)
        act = "picker-open";
    else if (ctx.mode === "drag" && nearTop && monitor.name !== ctx.current)
        act = "picker-monitor";
    else if (ctx.mode === "drag")
        act = "picker-hover";

    var out = { state: next, act: act, monitor: monitor };
    if (recheck > 0)
        out.recheck = recheck;
    return out;
}
