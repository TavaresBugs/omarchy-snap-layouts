const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const W = load("workspaces.js");

// The user's setup: eDP-1 (id 0) owns workspaces 1-10, DP-3 (id 1) owns 11-20.
const monitors = {
    0: { x: 1536, y: 0, w: 1280, h: 720 },
    1: { x: 0, y: 0, w: 1536, h: 864 }
};
const win = (ws, monitor, at, size, extra) => Object.assign(
    { address: "0x" + Math.random().toString(16).slice(2, 8), workspace: { id: ws }, monitor, at, size, focusHistoryID: 0 }, extra);
const ids = (strip) => strip.map((e) => e.id);

test("block, slot and label follow the monitor blocks of ten", () => {
    assert.deepEqual([1, 5, 10, 11, 15, 20].map(W.blockOf), [0, 0, 0, 1, 1, 1]);
    assert.deepEqual([1, 5, 10, 11, 15, 20].map(W.slotOf), [1, 5, 10, 1, 5, 10]);
    assert.deepEqual([1, 9, 10, 11, 20].map(W.labelOf), ["1", "9", "0", "1", "0"]);
});

test("the strip shows the five workspaces of the monitor being looked at", () => {
    assert.deepEqual(ids(W.buildStrip([], monitors, 11)), [11, 12, 13, 14, 15]);
    assert.deepEqual(ids(W.buildStrip([], monitors, 3)), [1, 2, 3, 4, 5]);
});

test("labels are the positions in the block, not the global ids", () => {
    const strip = W.buildStrip([], monitors, 13);
    assert.deepEqual(strip.map((e) => e.label), ["1", "2", "3", "4", "5"]);
});

test("windows of the other monitor's workspaces are not in this strip", () => {
    const strip = W.buildStrip([
        win(1, 0, [1540, 30], [1272, 686]),   // Spotify on the laptop panel's workspace 1
        win(11, 1, [4, 30], [762, 830])
    ], monitors, 11);
    assert.equal(strip.reduce((n, e) => n + e.count, 0), 1);
    assert.equal(strip.find((e) => e.id === 11).count, 1);
});

test("the same windows give the other monitor's strip", () => {
    const strip = W.buildStrip([win(1, 0, [1540, 30], [1272, 686]), win(11, 1, [4, 30], [762, 830])], monitors, 1);
    assert.deepEqual(ids(strip), [1, 2, 3, 4, 5]);
    assert.equal(strip[0].count, 1);
});

test("empty workspaces are still listed, with no windows", () => {
    const strip = W.buildStrip([win(11, 1, [4, 30], [10, 10])], monitors, 11);
    assert.equal(strip.length, 5);
    assert.deepEqual(strip.map((e) => e.count), [1, 0, 0, 0, 0]);
});

test("workspaces 6 to 10 appear only when they hold windows or are current", () => {
    const strip = W.buildStrip([win(17, 1, [0, 0], [10, 10])], monitors, 11);
    assert.deepEqual(ids(strip), [11, 12, 13, 14, 15, 17]);
    assert.deepEqual(ids(W.buildStrip([], monitors, 19)), [11, 12, 13, 14, 15, 19]);
});

test("window outlines are fractions of their monitor", () => {
    const [ws] = W.buildStrip([win(11, 1, [768, 0], [768, 864], { address: "a" })], monitors, 11);
    assert.deepEqual(ws.windows[0], { x: 0.5, y: 0, w: 0.5, h: 1, address: "a" });
});

test("outlines are measured from the monitor's own origin", () => {
    const strip = W.buildStrip([win(1, 0, [1536 + 640, 360], [640, 360], { address: "s" })], monitors, 1);
    const w = strip[0].windows[0];
    assert.deepEqual([w.x, w.y, w.w, w.h], [0.5, 0.5, 0.5, 0.5]);
});

test("a window that sticks out of its monitor is clipped", () => {
    const [ws] = W.buildStrip([win(11, 1, [-100, -50], [2000, 1000])], monitors, 11);
    const w = ws.windows[0];
    assert.ok(w.x >= 0 && w.y >= 0 && w.x + w.w <= 1 && w.y + w.h <= 1);
});

test("the most recently used window is drawn last, on top", () => {
    const [ws] = W.buildStrip([
        win(11, 1, [0, 0], [10, 10], { address: "recent", focusHistoryID: 0 }),
        win(11, 1, [0, 0], [10, 10], { address: "old", focusHistoryID: 7 }),
        win(11, 1, [0, 0], [10, 10], { address: "mid", focusHistoryID: 3 })
    ], monitors, 11);
    assert.deepEqual(ws.windows.map((w) => w.address), ["old", "mid", "recent"]);
});

test("minimized and special workspaces and unknown monitors are ignored", () => {
    const strip = W.buildStrip([
        win(-98, 1, [0, 0], [10, 10]), win(-99, 1, [0, 0], [10, 10]), win(12, 9, [0, 0], [10, 10])
    ], monitors, 11);
    assert.equal(strip.reduce((n, e) => n + e.count, 0), 0);
});

test("stepping moves through the strip and wraps", () => {
    const strip = W.buildStrip([], monitors, 11);
    assert.equal(W.stepWorkspace(strip, 11, 1), 12);
    assert.equal(W.stepWorkspace(strip, 15, 1), 11);
    assert.equal(W.stepWorkspace(strip, 11, -1), 15);
});

test("stepping from a workspace not in the strip lands on the first; empty strip stays", () => {
    const strip = W.buildStrip([], monitors, 11);
    assert.equal(W.stepWorkspace(strip, 99, 1), 11);
    assert.equal(W.stepWorkspace([], 7, 1), 7);
});
