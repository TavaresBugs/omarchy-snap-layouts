.pragma library

// How the overview moves. Two kinds of numbers live here, and they are kept
// apart on purpose:
//
//  - TOKENS: matters of taste (how long, which curve, how big a lift). One
//    place to change them.
//  - Everything else is worked out from where things really are, so it is
//    right for any layout: how far a selected card may grow (the room it has
//    inside the area windows can use) and when the workspace strip has to be
//    gone (before the first card heading back to its window would cross it).
//
// Pure functions, no Qt objects.

var TOKENS = {
    open:  { duration: 360, curve: [0.16, 1, 0.3, 1, 1, 1] },     // fast out, long soft landing
    close: { duration: 260, curve: [0.65, 0, 0.35, 1, 1, 1] },    // symmetrical ease
    stagger: 0.18,          // share of the animation over which cards leave one after another
    emphasisScale: 0.05,    // how much larger the selected card may be, at most
    emphasisLift: 6,        // how far the selected card may rise, at most (px)
    dim: 0,                 // how much of the theme's background the overview lays over the blurred wallpaper
    blur: 0.7,              // how much the overview blurs the wallpaper (0 sharp .. 1 the most)
    dimSpeed: 1.8,          // the dim reaches full opacity at progress 1 / dimSpeed
    chromeFrom: 0.55,       // icon and title appear once a card has travelled this far
    stripClearance: 12,     // gap kept between the strip and a card heading under it (px)
    stripClearMax: 0.8,     // the strip is always back by the time the animation is this far along
    // How long the small things take (ms): a hover, a state change, a fade, a lift, a pop, a
    // slide. Run through Style.duration, so they are 0 when the system has animations off.
    dur: { hover: 90, quick: 120, fade: 140, settle: 160, pop: 170, slideFade: 200, slide: 240 }
};

function clamp01(v) {
    return Math.max(0, Math.min(1, v));
}

function smoothstep(t) {
    var x = clamp01(t);
    return x * x * (3 - 2 * x);
}

// The card at `index` of `count` leaves its window after this share of the
// animation; the selected one (or the only one) leads.
function staggerDelay(index, count, selected) {
    return selected || count < 2 ? 0 : TOKENS.stagger * index / (count - 1);
}

// 0 while a card sits on its window, 1 once it is in place, for overall
// `progress` and the card's `delay`.
function travel(progress, delay) {
    return clamp01((progress - delay) / (1 - delay));
}

// How much the selected card may be enlarged (about its centre) and lifted
// without leaving `bounds`, the area windows can use. A card that fills that
// area, as a window filling the mosaic does, gets none, whatever its travel;
// one with room around it gets up to the tokens. Returns { scale, lift }.
function emphasis(x, y, w, h, bounds) {
    var scale = 1 + TOKENS.emphasisScale;
    var lift = TOKENS.emphasisLift;
    if (!bounds || w <= 0 || h <= 0)
        return { scale: scale, lift: lift };
    var left = x - bounds.x;
    var right = bounds.x + bounds.w - (x + w);
    var top = y - bounds.y;
    var bottom = bounds.y + bounds.h - (y + h);
    // Growing by a factor f about the centre adds (f - 1) * size / 2 on each side.
    var fx = 1 + 2 * Math.max(0, Math.min(left, right)) / w;
    var fy = 1 + 2 * Math.max(0, Math.min(top, bottom)) / h;
    var f = Math.min(scale, fx, fy);
    // What is left of the room above, after the growth, is how far it may rise.
    var above = top - (f - 1) * h / 2;
    return { scale: f, lift: Math.max(0, Math.min(lift, above)) };
}

// The overall progress below which the workspace strip must be gone: the
// largest, over the cards, of the progress at which a card heading back to its
// window reaches the strip (its top edge crossing `stripBottom`). Cards whose
// window lies below the strip never get there. `rects` are the layout's
// rectangles ({ y, ry } = top edge in place and on the window), `delays` the
// cards' delays. 0 when no card ever crosses.
function stripClear(rects, stripBottom, delays) {
    var clear = 0;
    var line = stripBottom + TOKENS.stripClearance;
    for (var i = 0; i < rects.length; i++) {
        var inPlace = rects[i].y, onWindow = rects[i].ry;
        if (!(onWindow < line) || !(inPlace > onWindow))
            continue;
        var t = clamp01((line - onWindow) / (inPlace - onWindow));
        var d = delays[i] || 0;
        clear = Math.max(clear, d + t * (1 - d));
    }
    return Math.min(clear, TOKENS.stripClearMax);
}

// How visible the strip is at overall `progress`: gone up to `clear`, fully
// there over the remaining time, eased.
function stripVisibility(progress, clear) {
    if (progress >= 1)
        return 1;
    var span = Math.max(0.1, (1 - clear) * 0.6);
    return smoothstep((progress - clear) / span);
}
