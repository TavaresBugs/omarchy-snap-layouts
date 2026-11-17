.pragma library
.import "shortcuts.js" as Shortcuts

// User options, read from this plugin's entry in ~/.config/omarchy/shell.json.
//
// The plugin is three products, each with a switch of its own:
//
//   { "id": "io.github.n0rthstar88.snap-layouts",
//     "winsaico": true,        // WinSaico, the fourth workspace mode (Super+L, the layout menu)
//     "autoFit": true,         //   its complement: windows share the screen by themselves
//     "overview": false,       // Alt+Tab: the window overview and the workspace strip
//     "snap": true,            // Snapping: drag to the top, an edge or a corner, and the picker
//     "edgeDwellMs": 120,      // how long to hold there before the preview shows
//     "edgeMargin": 12,        // px from the edge that count as "at the edge"
//     "edgeCorner": 60,        // px along an edge that count as a corner
//     "overviewScope": "workspace",    // "workspace" or "all"
//     "mainMonitor": "",               // connector shown big in the overview strip, e.g. "DP-3"
//     "pickerShortcut": "",            // "SUPER + Z": the plugin binds it for you; "" = none
//     "overviewShortcut": "",          // the overview's key; "" = ALT + TAB
//     "layoutShortcut": "",            // the layout key; "" = the one Omarchy uses (SUPER + L)
//     "layoutBackShortcut": "",        // the same, going the other way round (SUPER + ALT + L)
//     "autoFitShortcut": "" }          // a key that turns auto-fit on and off
//
// Anything missing or invalid falls back to the default, so a typo in the file
// can never break the plugin. Entries written by earlier versions still read right:
// "enabled": false turns the three products off, "dragToSnap" and "edgeSnap" (both
// false) turn Snapping off, and an "overviewShortcut" turns the overview on. The
// first change saved from the bar card rewrites the entry in the new form.

var DEFAULTS = {
    winsaico: true,
    autoFit: true,
    overview: false,
    snap: true,
    edgeDwellMs: 120,
    edgeMargin: 12,
    edgeCorner: 60,
    overviewScope: "workspace",
    mainMonitor: "",
    pickerShortcut: "",
    overviewShortcut: "",
    layoutShortcut: "",
    layoutBackShortcut: "",
    autoFitShortcut: ""
};

// The key a product takes when its shortcut option is empty and the product is on.
var OVERVIEW_KEY = "ALT + TAB";

// Options earlier versions wrote; saving rewrites the entry without them.
var LEGACY = ["enabled", "dragToSnap", "edgeSnap"];

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

function flag(value) {
    return typeof value === "boolean" ? value : null;
}

// Turn a raw plugin entry (or null) into complete, validated options.
function resolve(entry) {
    var e = entry || {};
    var off = e.enabled === false;
    var winsaico = flag(e.winsaico);
    var overview = flag(e.overview);
    var snap = flag(e.snap);
    var autoFit = flag(e.autoFit);
    return {
        winsaico: winsaico !== null ? winsaico : !off,
        autoFit: autoFit !== null ? autoFit : DEFAULTS.autoFit,
        overview: overview !== null ? overview : (!off && Shortcuts.valid(e.overviewShortcut)),
        snap: snap !== null ? snap : !(off || (e.dragToSnap === false && e.edgeSnap === false)),
        edgeDwellMs: number(e.edgeDwellMs, "edgeDwellMs"),
        edgeMargin: number(e.edgeMargin, "edgeMargin"),
        edgeCorner: number(e.edgeCorner, "edgeCorner"),
        overviewScope: SCOPES.indexOf(e.overviewScope) >= 0 ? e.overviewScope : DEFAULTS.overviewScope,
        mainMonitor: typeof e.mainMonitor === "string" && /^[A-Za-z0-9._:-]+$/.test(e.mainMonitor) ? e.mainMonitor : DEFAULTS.mainMonitor,
        pickerShortcut: Shortcuts.valid(e.pickerShortcut) ? e.pickerShortcut.trim() : DEFAULTS.pickerShortcut,
        overviewShortcut: Shortcuts.valid(e.overviewShortcut) ? e.overviewShortcut.trim() : DEFAULTS.overviewShortcut,
        layoutShortcut: Shortcuts.valid(e.layoutShortcut) ? e.layoutShortcut.trim() : DEFAULTS.layoutShortcut,
        layoutBackShortcut: Shortcuts.valid(e.layoutBackShortcut) ? e.layoutBackShortcut.trim() : DEFAULTS.layoutBackShortcut,
        autoFitShortcut: Shortcuts.valid(e.autoFitShortcut) ? e.autoFitShortcut.trim() : DEFAULTS.autoFitShortcut
    };
}

function isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

// This plugin's entry in a parsed shell.json. Once the plugin has a button in the
// bar, the shell keeps its settings in that bar entry rather than in plugins[]
// (see updateEntryInline in the shell), and a plugin enabled before that still has
// its old record there. Both are read, the bar entry winning, so nothing set
// earlier is lost. Null when there is neither.
function entryFrom(config, pluginId) {
    if (!isObject(config))
        return null;
    var found = null;
    function take(entry) {
        if (isObject(entry) && entry.id === pluginId)
            found = Object.assign(found || {}, entry);
    }
    if (Array.isArray(config.plugins))
        config.plugins.forEach(take);
    var layout = isObject(config.bar) && isObject(config.bar.layout) ? config.bar.layout : {};
    Object.keys(layout).forEach(function(section) {
        if (Array.isArray(layout[section]))
            layout[section].forEach(take);
    });
    return found;
}

// What to hand the shell to save changed options: the entry without its id and
// without the options earlier versions wrote, with the three products written out
// as they currently read (so an old entry is migrated by its first change).
function changedMany(entry, changes) {
    var now = resolve(entry);
    var out = Object.assign({}, entry || {});
    delete out.id;
    LEGACY.forEach(function(key) { delete out[key]; });
    out.winsaico = now.winsaico;
    out.overview = now.overview;
    out.snap = now.snap;
    Object.keys(changes).forEach(function(key) { out[key] = changes[key]; });
    return out;
}

function changed(entry, key, value) {
    var change = {};
    change[key] = value;
    return changedMany(entry, change);
}

// The key the overview answers to: the one set, or Alt+Tab.
function overviewKey(options) {
    return options.overviewShortcut !== "" ? options.overviewShortcut : OVERVIEW_KEY;
}

// The shortcuts that should be bound, by product: a product that is off binds
// nothing, so Omarchy's own keys (Alt+Tab cycling, the layout key) come back.
// `layoutKeys` are the keys Omarchy gives the layout cycle (see shortcuts.layoutKeys).
function wantedShortcuts(options, layoutKeys) {
    var keys = layoutKeys || {};
    return {
        picker: options.snap ? options.pickerShortcut : "",
        overview: options.overview ? overviewKey(options) : "",
        layout: options.winsaico ? (options.layoutShortcut || keys.layout || "") : "",
        layoutBack: options.winsaico ? (options.layoutBackShortcut || keys.layoutBack || "") : "",
        autoFit: options.winsaico ? options.autoFitShortcut : ""
    };
}
