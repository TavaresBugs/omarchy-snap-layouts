const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const M = load("motion.js");
const T = M.TOKENS;

// The area windows can use: 1532 x 834 from (2, 28).
const area = { x: 2, y: 28, w: 1532, h: 834 };

test("a card that fills the usable area is not enlarged or lifted, whatever else", () => {
    const e = M.emphasis(2, 28, 1532, 834, area);
    assert.equal(e.scale, 1);
    assert.equal(e.lift, 0);
});

test("a card with room around it gets the full emphasis", () => {
    const e = M.emphasis(400, 300, 700, 400, area);
    assert.equal(e.scale, 1 + T.emphasisScale);
    assert.equal(e.lift, T.emphasisLift);
});

test("room is the limit: the card may grow only as far as its tightest side allows", () => {
    // 10 px to the left and right of a 1000 px wide card: grows by at most 2 * 10 / 1000.
    const e = M.emphasis(12, 300, 1512, 400, area);
    assert.ok(Math.abs(e.scale - (1 + 2 * 10 / 1512)) < 1e-9);
    const tight = M.emphasis(12, 300, 1512, 400, area);
    assert.ok(tight.scale < 1 + T.emphasisScale);
});

test("the lift never takes the card above the area", () => {
    // 3 px of room above, none needed for growth sideways or down.
    const e = M.emphasis(400, 31, 700, 300, area);
    assert.ok(e.lift <= 3);
    assert.ok(e.lift >= 0);
});

test("without bounds the tokens apply", () => {
    assert.deepEqual(M.emphasis(0, 0, 10, 10, null), { scale: 1 + T.emphasisScale, lift: T.emphasisLift });
});

test("staggering: the selected card and a lone card lead; the rest follow in order", () => {
    assert.equal(M.staggerDelay(2, 5, true), 0);
    assert.equal(M.staggerDelay(0, 1, false), 0);
    assert.equal(M.staggerDelay(0, 4, false), 0);
    assert.ok(Math.abs(M.staggerDelay(3, 4, false) - T.stagger) < 1e-9);
    assert.ok(M.staggerDelay(1, 4, false) < M.staggerDelay(2, 4, false));
});

test("travel runs from 0 to 1 after the card's delay", () => {
    assert.equal(M.travel(0.5, 0), 0.5);
    assert.equal(M.travel(0.1, 0.2), 0);
    assert.equal(M.travel(1, 0.2), 1);
    assert.ok(Math.abs(M.travel(0.6, 0.2) - 0.5) < 1e-9);
});

test("the strip is never in the way of windows that lie below it", () => {
    const rects = [{ y: 400, ry: 200 }, { y: 420, ry: 260 }];
    assert.equal(M.stripClear(rects, 150, [0, 0]), 0);
});

test("a window that reaches up under the strip makes it leave before the card gets there", () => {
    // Window top at 30, card top in place at 300, strip bottom at 140 (+12 clearance).
    const clear = M.stripClear([{ y: 300, ry: 30 }], 140, [0]);
    assert.ok(Math.abs(clear - (152 - 30) / (300 - 30)) < 1e-9);
});

test("the first card to reach the strip decides, and its delay counts", () => {
    const rects = [{ y: 300, ry: 30 }, { y: 300, ry: 100 }];
    const early = M.stripClear(rects, 140, [0, 0]);
    const late = M.stripClear(rects, 140, [0, 0.18]);
    assert.ok(late >= early);
    assert.ok(early > 0 && early < 1);
});

test("strip visibility: gone up to the clear point, fully there by the end, never outside 0..1", () => {
    assert.equal(M.stripVisibility(0.3, 0.5), 0);
    assert.equal(M.stripVisibility(1, 0.5), 1);
    const mid = M.stripVisibility(0.65, 0.5);
    assert.ok(mid > 0 && mid < 1);
    assert.equal(M.stripVisibility(1, 1), 1);
});

test("the strip is always back in time, even when a card crosses it at the very end", () => {
    const clear = M.stripClear([{ y: 150, ry: 30 }], 140, [0]);
    assert.ok(clear <= T.stripClearMax);
});
