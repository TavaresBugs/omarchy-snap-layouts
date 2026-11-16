const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const N = load("navigation.js");

// Two rows: [0 1] on top, [2] below.
const rects = [{ x: 0, y: 0, w: 100, h: 60 }, { x: 120, y: 0, w: 100, h: 60 }, { x: 0, y: 80, w: 100, h: 60 }];
const cards = (over) => Object.assign({ strip: false, hasStrip: true, index: 0, rects, count: 3 }, over);
const key = (k, extra) => Object.assign({ key: k, ctrl: false, shift: false }, extra);

test("arrows move between windows", () => {
    assert.deepEqual(N.overviewKey(cards(), key("right")), { action: "select", index: 1 });
    assert.deepEqual(N.overviewKey(cards(), key("down")), { action: "select", index: 2 });
    assert.deepEqual(N.overviewKey(cards({ index: 2 }), key("up")), { action: "select", index: 0 });
});

test("up from the top row moves into the strip", () => {
    assert.deepEqual(N.overviewKey(cards(), key("up")), { action: "enterStrip" });
    assert.deepEqual(N.overviewKey(cards({ index: 1 }), key("up")), { action: "enterStrip" });
});

test("up from the top row stays put when there is no strip", () => {
    assert.deepEqual(N.overviewKey(cards({ hasStrip: false }), key("up")), { action: "select", index: 0 });
});

test("in the strip: left/right view other workspaces, shift moves the workspace, down returns", () => {
    const strip = cards({ strip: true });
    assert.deepEqual(N.overviewKey(strip, key("right")), { action: "stepWorkspace", delta: 1 });
    assert.deepEqual(N.overviewKey(strip, key("left")), { action: "stepWorkspace", delta: -1 });
    assert.deepEqual(N.overviewKey(strip, key("right", { shift: true })), { action: "swapWorkspace", delta: 1 });
    assert.deepEqual(N.overviewKey(strip, key("left", { shift: true })), { action: "swapWorkspace", delta: -1 });
    assert.deepEqual(N.overviewKey(strip, key("down")), { action: "leaveStrip" });
    assert.deepEqual(N.overviewKey(strip, key("enter")), { action: "activateWorkspace" });
    assert.deepEqual(N.overviewKey(strip, key("up")), { action: "none" });
});

test("a workspace with no windows keeps the focus on the strip", () => {
    const empty = cards({ count: 0, rects: [] });
    assert.deepEqual(N.overviewKey(empty, key("right")), { action: "stepWorkspace", delta: 1 });
    assert.deepEqual(N.overviewKey(empty, key("down")), { action: "none" });
    assert.deepEqual(N.overviewKey(empty, key("enter")), { action: "activateWorkspace" });
});

test("enter brings the selected window forward; nothing without windows or a strip", () => {
    assert.deepEqual(N.overviewKey(cards(), key("enter")), { action: "activate" });
    assert.deepEqual(N.overviewKey(cards({ count: 0, rects: [], hasStrip: false }), key("enter")), { action: "none" });
});

test("ctrl+arrows and page keys change workspace from the windows too", () => {
    assert.deepEqual(N.overviewKey(cards(), key("right", { ctrl: true })), { action: "stepWorkspace", delta: 1 });
    assert.deepEqual(N.overviewKey(cards(), key("pageup")), { action: "stepWorkspace", delta: -1 });
    assert.deepEqual(N.overviewKey(cards({ strip: true }), key("pagedown")), { action: "stepWorkspace", delta: 1 });
});

test("tab cycles through the windows and wraps", () => {
    assert.deepEqual(N.overviewKey(cards({ index: 2 }), key("tab")), { action: "select", index: 0 });
    assert.deepEqual(N.overviewKey(cards(), key("backtab")), { action: "select", index: 2 });
});
