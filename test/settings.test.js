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
    const o = S.resolve({ edgeSnap: false, edgeDwellMs: 500, edgeMargin: 20, edgeCorner: 120, overviewScope: "all" });
    assert.deepEqual(o, { edgeSnap: false, edgeDwellMs: 500, edgeMargin: 20, edgeCorner: 120, overviewScope: "all" });
});

test("unknown scope falls back to the default", () => {
    assert.equal(S.resolve({ overviewScope: "everything" }).overviewScope, "workspace");
    assert.equal(S.resolve({ overviewScope: 3 }).overviewScope, "workspace");
});

test("wrong types fall back to the default", () => {
    const o = S.resolve({ edgeSnap: "yes", edgeDwellMs: "fast", edgeMargin: null, edgeCorner: NaN });
    assert.equal(o.edgeSnap, true);
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
    const o = S.resolve({ id: "x", dragToSnap: true, whatever: 1 });
    assert.deepEqual(o, S.DEFAULTS);
});
