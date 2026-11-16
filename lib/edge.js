.pragma library

// Edge and corner snap: which zone is the pointer asking for while a window is
// dragged against a screen edge. Pure function, no Qt objects.

// Returns { layout, zone, key } or null.
//   monitor: { x, y, w, h }  logical, global coordinates
//   cursor:  { x, y }        global coordinates
//   opts:    { margin, corner }  how close counts as "at the edge", and how far
//            along an edge a corner reaches
//
// layout is a name from layouts.js INDEX ("halves", "quarters" or "full"):
//   left / right edge  -> half of the screen
//   corners            -> a quarter
//   top edge           -> the whole usable area
function edgeTarget(monitor, cursor, opts) {
    var lx = cursor.x - monitor.x;
    var ly = cursor.y - monitor.y;
    var e = opts.margin;
    var c = opts.corner;
    var nearL = lx <= e, nearR = lx >= monitor.w - e;
    var nearT = ly <= e, nearB = ly >= monitor.h - e;
    var cornerL = lx <= c, cornerR = lx >= monitor.w - c;
    var cornerT = ly <= c, cornerB = ly >= monitor.h - c;

    var layout = null, zone = 0;
    if ((nearL && cornerT) || (nearT && cornerL)) { layout = "quarters"; zone = 0; }
    else if ((nearR && cornerT) || (nearT && cornerR)) { layout = "quarters"; zone = 1; }
    else if ((nearL && cornerB) || (nearB && cornerL)) { layout = "quarters"; zone = 2; }
    else if ((nearR && cornerB) || (nearB && cornerR)) { layout = "quarters"; zone = 3; }
    else if (nearT) { layout = "full"; zone = 0; }
    else if (nearL) { layout = "halves"; zone = 0; }
    else if (nearR) { layout = "halves"; zone = 1; }

    if (layout === null)
        return null;
    return { layout: layout, zone: zone, key: layout + ":" + zone };
}
