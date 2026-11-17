.pragma library

// The corners of everything the plugin draws, from one number: the rounding of the
// real windows (`decoration:rounding`, which Omarchy's `Style.cornerRadius` mirrors).
//
// Nothing in the components writes a radius of its own. The rule is that a shape is
// rounded like the thing it stands for, and a thing around another is rounder by the
// gap between them, so the corners stay concentric and no seam shows:
//
//   zone   a window in its place: the thumbnail of a placed window, the outline of a
//          zone, the preview of where a window will land. Exactly the window's own
//          rounding, so a window that is swapped for its picture does not change shape.
//   thumb  a small picture off the desktop (the workspace strip).
//   card   a larger one (an overview card, the window being dragged). A card starts as
//          a `zone` on its window and ends as a `card`, see `between`.
//   panel  what holds cards or zones (the layout picker).
//   mini   a zone drawn inside a thumbnail of a layout.
//
// The other things taste decides are here too, by what they are for, so a component
// asks for "a resting outline" and not for 0.14:
//
//   ring    how thick a frame's ring is, from the real windows' border, so the ring that
//           stands in for a window's border is as thick as that border
//   ALPHA   how strong a tint is, by role
//   panelArea  where the cards go inside the snap assist's panel
//
// Pure functions, no Qt objects.

var STEP = { thumb: 2, card: 4, panel: 6 };

function radii(windowRadius) {
    var w = Number(windowRadius);
    if (!isFinite(w) || w < 0)
        w = 0;
    return {
        zone: w,
        thumb: w + STEP.thumb,
        card: w + STEP.card,
        panel: w + STEP.card + STEP.panel,
        mini: Math.max(2, Math.round(w / 2))
    };
}

// The radius of a shape that is `t` of the way (0..1) from one to another.
function between(from, to, t) {
    var k = Math.max(0, Math.min(1, t));
    return from + (to - from) * k;
}

// How thick the rings are, from the border Hyprland draws on a window (`border_size`,
// as read by lib/style.js). `strong` is the selection's: as thick as a window's own
// border. `rim` is a resting outline, half of it. An unreadable border is the usual 2.
function ring(border) {
    var b = border === null || border === "" ? NaN : Number(border);
    if (!isFinite(b) || b < 0)
        b = 2;
    b = Math.round(b);
    return { strong: Math.max(1, b), rim: Math.max(1, Math.round(b / 2)) };
}

// How strong a colour is laid over what is behind it, by what it is for. The colour
// itself always comes from the theme.
var ALPHA = {
    faint: 0.05,        // the fill of something at rest
    line: 0.14,         // an outline at rest
    lineStrong: 0.22,   // the same, raised: the main one, or under the pointer
    muted: 0.3,         // something inactive: a disabled arrow, a page dot, a drop target's picture
    label: 0.8,         // secondary text
    active: 0.9,        // something active, or a ring that says "this one"
    soft: 0.5,          // a ring that marks without insisting
    tint: 0.14,         // the accent laid lightly over something under the pointer
    tintStrong: 0.22,   // the accent laid over where a window will land
    veil: 0.5,          // behind a picture that has not arrived yet
    placeholder: 0.9,   // the same, for a card
    pane: 0.82,         // the fill of a small thumbnail
    solid: 0.96,        // a surface that has to be read over anything
    glass: 0.45,        // a chip over the wallpaper, at rest
    glassStrong: 0.62,  // the same, raised
    outline: 0.75,      // the edge of text drawn over a picture
    edge: 0.45,         // a thin edge drawn around a window inside a thumbnail
    shadow: 0.4,        // a soft shadow
    shadowStrong: 0.6   // the selection's
};

// Where the cards go inside the snap assist's panel (`w` x `h`): below the title, with
// room at the bottom, and for the pager when there is one. `m` is { pad, title, pager }:
// the panel's padding, the title's height and the pager's, from the theme's spacing.
function panelArea(w, h, paged, m) {
    var top = 2 * m.pad + m.title;
    var bottom = paged ? m.pad + m.pager : m.pad;
    return { x: m.pad, y: top, w: w - 2 * m.pad, h: h - top - bottom };
}
