const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const E = load("edge.js");

const monitor = { x: 0, y: 0, w: 1536, h: 864 };
const opts = { margin: 12, corner: 90 };
const at = (x, y, m = monitor) => E.edgeTarget(m, { x, y }, opts);

test("the middle of the screen asks for nothing", () => {
    assert.equal(at(768, 432), null);
    assert.equal(at(100, 432), null);
});

test("left and right edges ask for a half", () => {
    assert.deepEqual(at(3, 432), { layout: "halves", zone: 0, key: "halves:0" });
    assert.deepEqual(at(1533, 432), { layout: "halves", zone: 1, key: "halves:1" });
});

test("the top edge asks for the whole area", () => {
    assert.deepEqual(at(768, 3), { layout: "full", zone: 0, key: "full:0" });
});

test("corners ask for a quarter, whichever edge the pointer is on", () => {
    assert.equal(at(3, 3).layout, "quarters");
    assert.equal(at(3, 3).zone, 0);          // top-left
    assert.equal(at(1533, 3).zone, 1);       // top-right
    assert.equal(at(3, 861).zone, 2);        // bottom-left
    assert.equal(at(1533, 861).zone, 3);     // bottom-right
    // Along the top edge but within the corner reach.
    assert.equal(at(60, 3).layout, "quarters");
    assert.equal(at(60, 3).zone, 0);
    // Along the left edge but within the corner reach.
    assert.equal(at(3, 50).zone, 0);
});

test("the bottom edge alone does nothing", () => {
    assert.equal(at(768, 861), null);
});

test("corner wins over the plain edge it overlaps", () => {
    // Close to the top and to the left: quarter, not "full" and not "half".
    assert.equal(at(5, 5).layout, "quarters");
});

test("coordinates are taken relative to the monitor", () => {
    const second = { x: 1536, y: 0, w: 1280, h: 720 };
    assert.deepEqual(at(1536 + 3, 360, second), { layout: "halves", zone: 0, key: "halves:0" });
    assert.equal(at(1536 + 640, 360, second), null);
});

test("thresholds come from the options", () => {
    const tight = { margin: 2, corner: 10 };
    assert.equal(E.edgeTarget(monitor, { x: 8, y: 432 }, tight), null);
    assert.equal(E.edgeTarget(monitor, { x: 1, y: 432 }, tight).layout, "halves");
});
