const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const S = load("settings.js");

test("no entry gives the defaults", () => {
    assert.deepEqual(S.resolve(null), S.DEFAULTS);
    assert.deepEqual(S.resolve({}), S.DEFAULTS);
    assert.deepEqual(S.resolve(undefined), S.DEFAULTS);
});

test("the overview is limited to the current workspace by default", () => {
    assert.equal(S.resolve(null).overviewScope, "workspace");
});

test("valid values are used", () => {
    const o = S.resolve({ snap: false, winsaico: false, overview: true, edgeDwellMs: 500, edgeMargin: 20, edgeCorner: 120, overviewScope: "all", mainMonitor: "DP-3", pickerShortcut: "SUPER + Z", overviewShortcut: "ALT + TAB" });
    assert.deepEqual(o, { winsaico: false, autoFit: true, overview: true, snap: false, autoFitShortcut: "", layoutShortcut: "", layoutBackShortcut: "", edgeDwellMs: 500, edgeMargin: 20, edgeCorner: 120, overviewScope: "all", mainMonitor: "DP-3", pickerShortcut: "SUPER + Z", overviewShortcut: "ALT + TAB" });
});

test("unknown scope falls back to the default", () => {
    assert.equal(S.resolve({ overviewScope: "everything" }).overviewScope, "workspace");
    assert.equal(S.resolve({ overviewScope: 3 }).overviewScope, "workspace");
});

test("wrong types fall back to the default", () => {
    const o = S.resolve({ snap: "yes", edgeDwellMs: "fast", edgeMargin: null, edgeCorner: NaN });
    assert.equal(o.snap, true);
    assert.equal(o.edgeDwellMs, S.DEFAULTS.edgeDwellMs);
    assert.equal(o.edgeMargin, S.DEFAULTS.edgeMargin);
    assert.equal(o.edgeCorner, S.DEFAULTS.edgeCorner);
});

test("numbers are clamped to sane limits", () => {
    const low = S.resolve({ edgeDwellMs: -50, edgeMargin: 0, edgeCorner: 1 });
    assert.deepEqual([low.edgeDwellMs, low.edgeMargin, low.edgeCorner], [0, 1, 10]);
    const high = S.resolve({ edgeDwellMs: 99999, edgeMargin: 5000, edgeCorner: 5000 });
    assert.deepEqual([high.edgeDwellMs, high.edgeMargin, high.edgeCorner], [3000, 80, 400]);
});

test("unrelated keys in the entry are ignored", () => {
    const o = S.resolve({ id: "x", whatever: 1 });
    assert.deepEqual(o, S.DEFAULTS);
});

test("the main monitor is a connector name or empty", () => {
    assert.equal(S.resolve({}).mainMonitor, "");
    assert.equal(S.resolve({ mainMonitor: "eDP-1" }).mainMonitor, "eDP-1");
    assert.equal(S.resolve({ mainMonitor: "x'); evil('" }).mainMonitor, "");
    assert.equal(S.resolve({ mainMonitor: 4 }).mainMonitor, "");
});

test("shortcuts are written the way Omarchy writes them, and anything else is ignored", () => {
    assert.equal(S.resolve({ pickerShortcut: "SUPER + Z" }).pickerShortcut, "SUPER + Z");
    assert.equal(S.resolve({ overviewShortcut: " ALT + TAB " }).overviewShortcut, "ALT + TAB");
    assert.equal(S.resolve({}).pickerShortcut, "");
    assert.equal(S.resolve({ pickerShortcut: "HYPER + Z" }).pickerShortcut, "");
    assert.equal(S.resolve({ overviewShortcut: "ALT + TAB'); os.execute('x" }).overviewShortcut, "");
    assert.equal(S.resolve({ overviewShortcut: 12 }).overviewShortcut, "");
});

test("the products start as the plugin's defaults: WinSaico and Snapping on, the overview off", () => {
    const o = S.resolve(null);
    assert.deepEqual([o.winsaico, o.snap, o.overview, o.autoFit], [true, true, false, true]);
});

test("each product has its own switch", () => {
    const o = S.resolve({ winsaico: false, overview: true, snap: false });
    assert.deepEqual([o.winsaico, o.overview, o.snap], [false, true, false]);
    assert.equal(S.resolve({ winsaico: "no", overview: 1, snap: null }).winsaico, true);
    assert.equal(S.resolve({ overview: "yes" }).overview, false);
});

test("an entry from an earlier version still reads right", () => {
    // the old master switch turned everything off
    const off = S.resolve({ enabled: false, overviewShortcut: "ALT + TAB" });
    assert.deepEqual([off.winsaico, off.overview, off.snap], [false, false, false]);
    // snapping was two switches; only both off means off
    assert.equal(S.resolve({ dragToSnap: false }).snap, true);
    assert.equal(S.resolve({ edgeSnap: false }).snap, true);
    assert.equal(S.resolve({ dragToSnap: false, edgeSnap: false }).snap, false);
    // having given the overview a key meant using it
    assert.equal(S.resolve({ overviewShortcut: "ALT + TAB" }).overview, true);
    // an explicit new-style switch wins over the old ones
    assert.equal(S.resolve({ enabled: false, snap: true }).snap, true);
});

const ID = "io.github.n0rthstar88.snap-layouts";

test("entryFrom reads the plugin's record", () => {
    const config = { plugins: [{ id: "other", x: 1 }, { id: ID, edgeSnap: false }] };
    assert.deepEqual(S.entryFrom(config, ID), { id: ID, edgeSnap: false });
});

test("entryFrom reads the bar entry too, which wins over the plugin's record", () => {
    const config = {
        plugins: [{ id: ID, edgeSnap: false, dragToSnap: true }],
        bar: { layout: { right: [{ id: "omarchy.tray" }, { id: ID, edgeSnap: true }] } }
    };
    assert.deepEqual(S.entryFrom(config, ID), { id: ID, edgeSnap: true, dragToSnap: true });
});

test("entryFrom is null when there is no entry, and survives odd shapes", () => {
    assert.equal(S.entryFrom(null, ID), null);
    assert.equal(S.entryFrom({}, ID), null);
    assert.equal(S.entryFrom({ plugins: "x", bar: { layout: { right: "y" } } }, ID), null);
    assert.equal(S.entryFrom({ bar: { layout: { right: [null, "omarchy.tray", { id: ID }] } } }, ID).id, ID);
});

test("saving writes the entry without its id and the old options, with the products spelled out", () => {
    const entry = { id: ID, edgeMargin: 20 };
    assert.deepEqual(S.changed(entry, "snap", false), { edgeMargin: 20, winsaico: true, overview: false, snap: false });
    assert.deepEqual(entry, { id: ID, edgeMargin: 20 });
    const old = { id: ID, enabled: true, dragToSnap: true, edgeSnap: true, overviewShortcut: "ALT + TAB", autoFit: false };
    assert.deepEqual(S.changed(old, "autoFit", true), { overviewShortcut: "ALT + TAB", autoFit: true, winsaico: true, overview: true, snap: true });
    assert.deepEqual(S.changed(null, "overview", true), { winsaico: true, overview: true, snap: true });
});

test("a product that is off binds nothing", () => {
    const keys = { layout: "SUPER + L", layoutBack: "SUPER + ALT + L" };
    const on = S.resolve({ overview: true, pickerShortcut: "SUPER + Z" });
    assert.deepEqual(S.wantedShortcuts(on, keys), { picker: "SUPER + Z", overview: "ALT + TAB", layout: "SUPER + L", layoutBack: "SUPER + ALT + L", autoFit: "" });
    const off = S.resolve({ winsaico: false, snap: false, overview: false, pickerShortcut: "SUPER + Z", overviewShortcut: "CTRL + TAB" });
    assert.deepEqual(S.wantedShortcuts(off, keys), { picker: "", overview: "", layout: "", layoutBack: "", autoFit: "" });
});

test("the overview answers to Alt+Tab unless it was given another key", () => {
    assert.equal(S.overviewKey(S.resolve({ overview: true })), "ALT + TAB");
    assert.equal(S.overviewKey(S.resolve({ overview: true, overviewShortcut: "CTRL + TAB" })), "CTRL + TAB");
});

test("WinSaico takes the layout keys Omarchy has them on, unless the options name others", () => {
    assert.equal(S.resolve(null).layoutShortcut, "");
    assert.equal(S.resolve({ layoutShortcut: "not a key +" }).layoutShortcut, "");
    const keys = { layout: "SUPER + L", layoutBack: "SUPER + ALT + L" };
    assert.equal(S.wantedShortcuts(S.resolve(null), keys).layout, "SUPER + L");
    assert.equal(S.wantedShortcuts(S.resolve({ layoutShortcut: "SUPER + K" }), keys).layout, "SUPER + K");
    assert.equal(S.wantedShortcuts(S.resolve(null), null).layout, "");
    assert.equal(S.wantedShortcuts(S.resolve({ winsaico: false }), keys).layout, "");
});

test("changedMany sets several options in one entry", () => {
    const entry = { id: ID, edgeMargin: 30 };
    assert.deepEqual(S.changedMany(entry, { layoutShortcut: "SUPER + L", layoutBackShortcut: "SUPER + ALT + L" }),
        { edgeMargin: 30, winsaico: true, overview: false, snap: true, layoutShortcut: "SUPER + L", layoutBackShortcut: "SUPER + ALT + L" });
    assert.deepEqual(entry, { id: ID, edgeMargin: 30 });
});

test("auto-fit is on unless the entry turns it off", () => {
    assert.equal(S.resolve(null).autoFit, true);
    assert.equal(S.resolve({ autoFit: false }).autoFit, false);
    assert.equal(S.resolve({ autoFit: "no" }).autoFit, true);
    assert.equal(S.resolve({ autoFitShortcut: "SUPER + SHIFT + L" }).autoFitShortcut, "SUPER + SHIFT + L");
});
