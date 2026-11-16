.pragma library

// Layout and navigation of the window overview (the Alt+Tab view). Pure
// functions, no Qt objects, so they are covered by unit tests.

// Layout tokens: how the thumbnails are spaced, and how much of the screen the
// overview keeps clear around them.
var LAYOUT = { gapX: 40, gapY: 62, maxHeightFraction: 0.62 };
var ASSIST_LAYOUT = { gapX: 28, gapY: 56, maxHeightFraction: 0.7 };
var MARGIN = { side: 70, bottom: 70, top: 50, topWithStrip: 138 };

// Where the overview's thumbnails may go on a monitor: below the bar (and
// below the workspace strip when there is one), with a margin around.
//   monitor: { w, h, reserved: [l, t, r, b] } in logical px, overlay-local
function area(monitor, hasStrip) {
    var top = monitor.reserved[1] + (hasStrip ? MARGIN.topWithStrip : MARGIN.top);
    return {
        x: MARGIN.side,
        y: top,
        w: monitor.w - 2 * MARGIN.side,
        h: monitor.h - top - MARGIN.bottom
    };
}

// Thumbnails are arranged like GNOME's overview: rows of equal height, in the
// reading order of where the windows really are.
//
//   windows: [{ at: [x, y], size: [w, h], monitor: { x, y, h } }]   (global logical px)
//   area:    { x, y, w, h }   where the thumbnails may go
//   opts:    { gapX, gapY, maxHeightFraction }
//
// Returns one rect per window, in the same order as `windows`:
//   { x, y, w, h }          where it ends up in the overview
//   { rx, ry, rw, rh }      where the window really is (monitor-local), the
//                           starting point of the opening animation
function layoutRows(windows, area, opts) {
    var n = windows.length;
    if (n === 0)
        return [];

    var items = windows.map(function(win, i) {
        var m = win.monitor;
        var rw = Math.max(1, win.size[0]), rh = Math.max(1, win.size[1]);
        var lx = win.at[0] - m.x, ly = win.at[1] - m.y;
        return {
            i: i,
            aspect: Math.max(0.55, Math.min(2.6, rw / rh)),
            cx: lx + rw / 2,
            // Windows whose centres fall in the same 40%-of-screen-height band
            // are read left to right as one row.
            band: Math.floor((ly + rh / 2) / (m.h * 0.4)),
            rx: lx, ry: ly, rw: rw, rh: rh
        };
    });
    var reading = items.slice().sort(function(a, b) {
        return a.band !== b.band ? a.band - b.band : a.cx - b.cx;
    });

    var rows = splitIntoRows(reading, columnsFor(n));

    // One common height for every row: it must fit the widest row and the total
    // height, and is capped so that a lone window is not enormous.
    var fit = Infinity;
    rows.forEach(function(row) {
        var aspects = 0;
        row.forEach(function(it) { aspects += it.aspect; });
        fit = Math.min(fit, (area.w - opts.gapX * (row.length - 1)) / aspects);
    });
    var h = Math.min(fit, (area.h - opts.gapY * (rows.length - 1)) / rows.length,
                     area.h * opts.maxHeightFraction);

    var out = new Array(n);
    var totalH = h * rows.length + opts.gapY * (rows.length - 1);
    var y = area.y + Math.max(0, (area.h - totalH) / 2);
    rows.forEach(function(row) {
        var rowW = opts.gapX * (row.length - 1);
        row.forEach(function(it) { rowW += it.aspect * h; });
        var x = area.x + (area.w - rowW) / 2;
        row.forEach(function(it) {
            var w = it.aspect * h;
            out[it.i] = {
                x: Math.round(x), y: Math.round(y), w: Math.round(w), h: Math.round(h),
                rx: it.rx, ry: it.ry, rw: it.rw, rh: it.rh
            };
            x += w + opts.gapX;
        });
        y += h + opts.gapY;
    });
    return out;
}

// How many thumbnails per row:
//   1 -> 1 | 2 -> 2 side by side | 3 -> 2+1 | 4 -> 2+2 | 5 -> 3+2 | 6 -> 3+3 | more -> 4 per row
function columnsFor(count) {
    if (count <= 2)
        return count;
    if (count <= 4)
        return 2;
    return count <= 6 ? 3 : 4;
}

function splitIntoRows(list, columns) {
    var rows = [];
    for (var pos = 0; pos < list.length; pos += columns)
        rows.push(list.slice(pos, pos + columns));
    return rows;
}

// The window an arrow key should select: the nearest one in that direction
// ("up", "down", "left", "right"). Candidates lying more sideways than the
// direction asked (outside a cone) are penalised. Returns `index` if there is
// nothing in that direction.
function neighbor(rects, index, dir) {
    var cur = rects[index];
    if (!cur)
        return index;
    var horizontal = dir === "left" || dir === "right";
    var cx = cur.x + cur.w / 2, cy = cur.y + cur.h / 2;
    var best = -1, bestScore = Infinity;
    for (var i = 0; i < rects.length; i++) {
        if (i === index)
            continue;
        var dx = rects[i].x + rects[i].w / 2 - cx;
        var dy = rects[i].y + rects[i].h / 2 - cy;
        if ((dir === "up" && dy >= -4) || (dir === "down" && dy <= 4)
                || (dir === "left" && dx >= -4) || (dir === "right" && dx <= 4))
            continue;
        var score = horizontal ? Math.abs(dx) + 2.5 * Math.abs(dy)
                               : Math.abs(dy) + 2.5 * Math.abs(dx);
        if (score < bestScore) {
            bestScore = score;
            best = i;
        }
    }
    return best >= 0 ? best : index;
}

// Tab / Shift+Tab: next or previous, wrapping around.
function step(index, delta, count) {
    return count === 0 ? index : ((index + delta) % count + count) % count;
}
