const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const W = load("workspaces.js");

const monitors = {
    0: { x: 1536, y: 0, w: 1280, h: 720 },
    1: { x: 0, y: 0, w: 1536, h: 864 }
};
const win = (ws, monitor, at, size) => ({ workspace: { id: ws }, monitor, at, size });

test("windows are grouped by workspace and workspaces sorted", () => {
    const strip = W.buildStrip([
        win(11, 1, [4, 30], [762, 830]),
        win(1, 0, [1540, 30], [1272, 686]),
        win(11, 1, [770, 30], [762, 830])
    ], monitors, 11);
    assert.deepEqual(strip.filter((e) => !e.isNew).map((e) => [e.id, e.count]), [[1, 1], [11, 2]]);
});

test("window outlines are fractions of their monitor", () => {
    const [ws] = W.buildStrip([win(11, 1, [768, 0], [768, 864])], monitors, 11);
    const w = ws.windows[0];
    assert.equal(w.x, 0.5);
    assert.equal(w.y, 0);
    assert.equal(w.w, 0.5);
    assert.equal(w.h, 1);
});

test("outlines are measured from the monitor's own origin", () => {
    const strip = W.buildStrip([win(1, 0, [1536 + 640, 360], [640, 360])], monitors, 1);
    const w = strip.find((e) => e.id === 1).windows[0];
    assert.deepEqual([w.x, w.y, w.w, w.h], [0.5, 0.5, 0.5, 0.5]);
});

test("a window that sticks out of its monitor is clipped", () => {
    const [ws] = W.buildStrip([win(1, 1, [-100, -50], [2000, 1000])], monitors, 1);
    const w = ws.windows[0];
    assert.ok(w.x >= 0 && w.y >= 0 && w.x + w.w <= 1 && w.y + w.h <= 1);
});

test("the current workspace is listed even when empty", () => {
    const strip = W.buildStrip([win(1, 0, [1540, 30], [100, 100])], monitors, 4);
    assert.deepEqual(strip.filter((e) => !e.isNew).map((e) => e.id), [1, 4]);
    assert.equal(strip.find((e) => e.id === 4).count, 0);
});

test("minimized and special workspaces are ignored", () => {
    const strip = W.buildStrip([win(-98, 1, [0, 0], [100, 100]), win(-99, 1, [0, 0], [100, 100])], monitors, 11);
    assert.deepEqual(strip.filter((e) => !e.isNew).map((e) => e.id), [11]);
});

test("a window on an unknown monitor is skipped, not fatal", () => {
    const strip = W.buildStrip([win(5, 9, [0, 0], [100, 100])], monitors, 1);
    assert.deepEqual(strip.filter((e) => !e.isNew).map((e) => e.id), [1]);
});

test("the last entry is an empty slot for the smallest free workspace", () => {
    const strip = W.buildStrip([win(1, 1, [0, 0], [10, 10]), win(2, 1, [0, 0], [10, 10]), win(4, 1, [0, 0], [10, 10])], monitors, 1);
    const last = strip[strip.length - 1];
    assert.equal(last.isNew, true);
    assert.equal(last.id, 3);
    assert.deepEqual(last.windows, []);
});

test("no empty slot when every workspace is taken", () => {
    const all = [];
    for (let n = 1; n <= 10; n++) all.push(win(n, 1, [0, 0], [10, 10]));
    const strip = W.buildStrip(all, monitors, 1);
    assert.equal(strip.some((e) => e.isNew), false);
    assert.equal(W.nextFree([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), 0);
});

test("stepping moves between real workspaces and wraps, skipping the new slot", () => {
    const strip = W.buildStrip([win(1, 1, [0, 0], [10, 10]), win(11, 1, [0, 0], [10, 10])], monitors, 11);
    assert.equal(W.stepWorkspace(strip, 11, 1), 1);
    assert.equal(W.stepWorkspace(strip, 1, 1), 11);
    assert.equal(W.stepWorkspace(strip, 1, -1), 11);
    assert.equal(W.stepWorkspace(strip, 11, -1), 1);
});

test("stepping from an unknown workspace lands on the first", () => {
    const strip = W.buildStrip([win(2, 1, [0, 0], [10, 10]), win(5, 1, [0, 0], [10, 10])], monitors, 2);
    assert.equal(W.stepWorkspace(strip, 99, 1), 2);
    assert.equal(W.stepWorkspace([], 7, 1), 7);
});
