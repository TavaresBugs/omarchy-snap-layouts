.pragma library

// Snap layouts and everything that is pure geometry about them: where a zone
// lands on screen, and how the layout picker card is laid out and hit-tested.
//
// No Quickshell or Qt objects in here, so the file can be unit tested with node
// (see test/). Coordinates are logical pixels. A "monitor" is the object built by
// monitors.js: { x, y, w, h, reserved: [left, top, right, bottom] }.

// Zones are [x, y, width, height] as fractions of the usable screen area.
var LAYOUTS = [
    [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]],
    [[0, 0, 2 / 3, 1], [2 / 3, 0, 1 / 3, 1]],
    [[0, 0, 1 / 3, 1], [1 / 3, 0, 2 / 3, 1]],
    [[0, 0, 1 / 3, 1], [1 / 3, 0, 1 / 3, 1], [2 / 3, 0, 1 / 3, 1]],
    [[0, 0, 0.5, 1], [0.5, 0, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]],
    [[0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5], [0, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]],
    // Not offered by the picker: the whole usable area, used by edge snap.
    [[0, 0, 1, 1]]
];

// Layouts the rest of the code refers to by name.
var INDEX = { halves: 0, quarters: 5, full: 6 };

// The first PICKER_COUNT layouts are shown in the picker card.
var PICKER_COUNT = 6;

var EPS = 0.001;

// Edges of a zone, inset by half the inner gap on sides that touch a neighbour.
function zoneEdges(z, left, top, width, height, half) {
    return {
        x1: left + z[0] * width + (z[0] > EPS ? half : 0),
        x2: left + (z[0] + z[2]) * width - (z[0] + z[2] < 1 - EPS ? half : 0),
        y1: top + z[1] * height + (z[1] > EPS ? half : 0),
        y2: top + (z[1] + z[3]) * height - (z[1] + z[3] < 1 - EPS ? half : 0)
    };
}

// Where a zone lands on screen, in global logical pixels, already inset for gaps
// and the window border. gaps = { outer, inner, border }.
function zoneScreenRect(monitor, gaps, layoutIndex, zoneIndex) {
    var res = monitor.reserved;
    var left = monitor.x + res[0] + gaps.outer;
    var top = monitor.y + res[1] + gaps.outer;
    var width = monitor.w - res[0] - res[2] - 2 * gaps.outer;
    var height = monitor.h - res[1] - res[3] - 2 * gaps.outer;
    var e = zoneEdges(LAYOUTS[layoutIndex][zoneIndex], left, top, width, height, gaps.inner / 2);
    // Round the edges, not the sizes, so neighbours share an exact edge.
    var b = gaps.border;
    var l = Math.round(e.x1) + b;
    var r = Math.round(e.x2) - b;
    var t = Math.round(e.y1) + b;
    var bt = Math.round(e.y2) - b;
    return { x: l, y: t, w: r - l, h: bt - t };
}

// A zone inside a layout thumbnail, relative to that thumbnail.
function zoneThumbRect(layoutIndex, zoneIndex, thumbW, thumbH) {
    var inset = 4;
    var e = zoneEdges(LAYOUTS[layoutIndex][zoneIndex], inset, inset,
                      thumbW - 2 * inset, thumbH - 2 * inset, 1.5);
    return { x: e.x1, y: e.y1, w: e.x2 - e.x1, h: e.y2 - e.y1 };
}

// ---- Picker card -------------------------------------------------------------
// card = { padding, gap, thumbHeight }. Coordinates are local to the monitor.

function thumbWidth(monitor, card) {
    var aspect = monitor ? monitor.w / monitor.h : 16 / 9;
    return Math.round(card.thumbHeight * Math.max(1.3, Math.min(aspect, 2.4)));
}

function cardRect(monitor, card) {
    var n = PICKER_COUNT;
    var w = 2 * card.padding + n * thumbWidth(monitor, card) + (n - 1) * card.gap;
    var h = 2 * card.padding + card.thumbHeight;
    var mw = monitor ? monitor.w : w;
    var top = monitor ? monitor.reserved[1] : 0;
    return { x: Math.round((mw - w) / 2), y: top + 12, w: w, h: h };
}

function thumbRect(monitor, card, i) {
    var c = cardRect(monitor, card);
    var tw = thumbWidth(monitor, card);
    return {
        x: c.x + card.padding + i * (tw + card.gap),
        y: c.y + card.padding,
        w: tw,
        h: card.thumbHeight
    };
}

// Which picker zone is under (lx, ly), or { layout: -1, zone: -1 }.
function hitTest(monitor, card, lx, ly) {
    for (var i = 0; i < PICKER_COUNT; i++) {
        var t = thumbRect(monitor, card, i);
        if (lx < t.x || lx >= t.x + t.w || ly < t.y || ly >= t.y + t.h)
            continue;
        for (var j = 0; j < LAYOUTS[i].length; j++) {
            var z = zoneThumbRect(i, j, t.w, t.h);
            // Generous hit boxes: the gaps between zones count too.
            if (lx >= t.x + z.x - 2 && lx < t.x + z.x + z.w + 2
                    && ly >= t.y + z.y - 2 && ly < t.y + z.y + z.h + 2)
                return { layout: i, zone: j };
        }
    }
    return { layout: -1, zone: -1 };
}
