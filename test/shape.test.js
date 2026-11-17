const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const S = load("shape.js");

test("a zone has exactly the windows' rounding, and what holds it is rounder", () => {
    const r = S.radii(6);
    assert.equal(r.zone, 6);
    assert.ok(r.zone < r.thumb && r.thumb < r.card && r.card < r.panel);
});

test("the radii follow the system: no rounding gives square zones", () => {
    assert.equal(S.radii(0).zone, 0);
    assert.equal(S.radii(12).zone, 12);
    assert.equal(S.radii(12).card, S.radii(6).card + 6);
});

test("an unreadable rounding is treated as none", () => {
    for (const bad of [undefined, null, "x", -3, NaN])
        assert.equal(S.radii(bad).zone, 0);
});

test("a panel's corner is its card's plus the gap, so they are concentric", () => {
    const r = S.radii(6);
    assert.equal(r.panel - r.card, S.STEP.panel);
});

test("between runs from one radius to the other and stays inside", () => {
    assert.equal(S.between(6, 10, 0), 6);
    assert.equal(S.between(6, 10, 1), 10);
    assert.equal(S.between(6, 10, 0.5), 8);
    assert.equal(S.between(6, 10, 3), 10);
    assert.equal(S.between(6, 10, -1), 6);
});

test("the rings follow the windows' border: strong is as thick, the rim half", () => {
    assert.deepEqual(S.ring(2), { strong: 2, rim: 1 });
    assert.deepEqual(S.ring(4), { strong: 4, rim: 2 });
    assert.deepEqual(S.ring(1), { strong: 1, rim: 1 });
    assert.deepEqual(S.ring(0), { strong: 1, rim: 1 });
});

test("an unknown border gives the usual rings", () => {
    for (const bad of [-1, undefined, null, "x", NaN])
        assert.deepEqual(S.ring(bad), { strong: 2, rim: 1 });
});

test("every strength is a share, and the stronger of a pair is stronger", () => {
    for (const [name, v] of Object.entries(S.ALPHA))
        assert.ok(v > 0 && v < 1, name);
    assert.ok(S.ALPHA.line < S.ALPHA.lineStrong);
    assert.ok(S.ALPHA.shadow < S.ALPHA.shadowStrong);
    assert.ok(S.ALPHA.glass < S.ALPHA.glassStrong);
});

test("the assist panel's area leaves the title above and the pager below", () => {
    const m = { pad: 24, title: 16, pager: 28 };
    assert.deepEqual(S.panelArea(500, 400, false, m), { x: 24, y: 64, w: 452, h: 312 });
    assert.deepEqual(S.panelArea(500, 400, true, m), { x: 24, y: 64, w: 452, h: 284 });
});
