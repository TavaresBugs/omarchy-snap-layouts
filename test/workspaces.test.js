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
    assert.deepEqual(ws.windows[0], { x: 0.5, y: 0, w: 0.5, h: 1, address: "a", floating: false, floatSpace: false });
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

// Both monitors with a workspace showing: laptop panel on 1, the other on 11.
const showing = {
    0: { id: 0, name: "eDP-1", workspaceId: 1, x: 1536, y: 0, w: 1280, h: 720 },
    1: { id: 1, name: "DP-3", workspaceId: 11, x: 0, y: 0, w: 1536, h: 864 }
};

test("the monitor owning a workspace is the one showing its block", () => {
    assert.equal(W.monitorFor(13, showing).name, "DP-3");
    assert.equal(W.monitorFor(4, showing).name, "eDP-1");
    assert.equal(W.monitorFor(25, showing), null);
});

test("screens: an external monitor is the main one unless chosen otherwise, whichever screen is looked at", () => {
    const fromLaptop = W.screens([], showing, 1, "");
    const fromOther = W.screens([], showing, 11, "");
    assert.deepEqual(fromLaptop.map((s) => s.name), ["DP-3", "eDP-1"]);
    assert.deepEqual(fromOther.map((s) => s.name), ["DP-3", "eDP-1"]);
    assert.deepEqual(fromOther.map((s) => s.main), [true, false]);
});

test("screens: a named main monitor goes first, an unknown name is ignored", () => {
    assert.deepEqual(W.screens([], showing, 1, "eDP-1").map((s) => s.name), ["eDP-1", "DP-3"]);
    assert.deepEqual(W.screens([], showing, 1, "nope").map((s) => s.name), ["DP-3", "eDP-1"]);
});

test("screens: without internal panels the first block is main", () => {
    const two = { 0: { id: 0, name: "DP-1", workspaceId: 1, x: 0, y: 0, w: 1920, h: 1080 }, 1: { id: 1, name: "HDMI-A-1", workspaceId: 11, x: 1920, y: 0, w: 1920, h: 1080 } };
    assert.deepEqual(W.screens([], two, 11, "").map((s) => s.name), ["DP-1", "HDMI-A-1"]);
});

test("direction follows the strips, main first", () => {
    const strips = W.screens([], showing, 1, "");      // DP-3 (11-15) then eDP-1 (1-5)
    assert.equal(W.direction(strips, 11, 12), 1);
    assert.equal(W.direction(strips, 12, 11), -1);
    assert.equal(W.direction(strips, 15, 1), 1);
    assert.equal(W.direction(strips, 3, 3), 0);
    assert.equal(W.direction(strips, 3, 99), 0);
});

test("each screen's strip is its own block, with its windows", () => {
    const [main, other] = W.screens([win(11, 1, [4, 30], [762, 830])], showing, 1, "");
    assert.deepEqual(main.entries.map((e) => e.id), [11, 12, 13, 14, 15]);
    assert.deepEqual(other.entries.map((e) => e.id), [1, 2, 3, 4, 5]);
    assert.equal(main.entries[0].count, 1);
    assert.equal(main.workspaceId, 11);
    assert.ok(Math.abs(main.aspect - 1536 / 864) < 1e-9);
});

test("a viewed workspace past the fifth is shown even when empty", () => {
    const [main] = W.screens([], showing, 17, "");
    assert.deepEqual(main.entries.map((e) => e.id), [11, 12, 13, 14, 15, 17]);
});

test("a single monitor gives a single strip", () => {
    assert.equal(W.screens([], { 1: showing[1] }, 11, "").length, 1);
});

test("entriesFor finds the strip holding a workspace", () => {
    const strips = W.screens([], showing, 1, "");
    assert.deepEqual(W.entriesFor(strips, 3).map((e) => e.id), [1, 2, 3, 4, 5]);
    assert.deepEqual(W.entriesFor(strips, 99).map((e) => e.id), [11, 12, 13, 14, 15]);
    assert.deepEqual(W.entriesFor([], 1), []);
});

// ---- drop preview ----
const outline = (address, x, y, w, h, extra) => Object.assign({ x, y, w, h, address, floating: false, floatSpace: false }, extra);
const entryOf = (...windows) => ({ id: 12, windows, count: windows.length });
const dragged = (extra) => Object.assign({ address: "new", floating: false, pinned: false }, extra);
const wide = 16 / 9;

test("dropping onto an empty workspace fills it", () => {
    const p = W.dropPreview(entryOf(), dragged(), wide);
    assert.deepEqual(p.slot, { x: 0, y: 0, w: 1, h: 1 });
    assert.equal(p.tile, true);
});

test("dropping next to one full-screen window splits it 50/50, new window on the right", () => {
    const p = W.dropPreview(entryOf(outline("a", 0, 0, 1, 1)), dragged(), wide);
    assert.deepEqual(p.slot, { x: 0.5, y: 0, w: 0.5, h: 1 });
    assert.deepEqual(p.windows.map((w) => [w.x, w.w]), [[0, 0.5]]);
});

test("the most recently used tiled window is the one that splits", () => {
    const p = W.dropPreview(entryOf(outline("old", 0, 0, 0.5, 1), outline("recent", 0.5, 0, 0.5, 1)), dragged(), wide);
    assert.deepEqual(p.windows.map((w) => w.address), ["old", "recent"]);
    assert.deepEqual(p.windows[0], outline("old", 0, 0, 0.5, 1));
    assert.deepEqual(p.slot, { x: 0.5, y: 0.5, w: 0.5, h: 0.5 });   // a tall half splits top/bottom
    assert.equal(p.windows[1].h, 0.5);
});

test("a window already on that workspace is not counted twice", () => {
    const p = W.dropPreview(entryOf(outline("new", 0, 0, 1, 1)), dragged(), wide);
    assert.deepEqual(p.slot, { x: 0, y: 0, w: 1, h: 1 });
    assert.equal(p.windows.length, 0);
});

test("a floating window is tiled on arrival only next to tiled windows", () => {
    const next = W.dropPreview(entryOf(outline("a", 0, 0, 1, 1)), dragged({ floating: true }), wide);
    assert.equal(next.tile, true);
    const alone = W.dropPreview(entryOf(), dragged({ floating: true }), wide);
    assert.equal(alone.tile, false);
    assert.equal(alone.slot, null);
    const pinned = W.dropPreview(entryOf(outline("a", 0, 0, 1, 1)), dragged({ floating: true, pinned: true }), wide);
    assert.equal(pinned.tile, false);
});

test("floating windows never split, and floating workspaces stay floating", () => {
    const over = W.dropPreview(entryOf(outline("t", 0, 0, 1, 1), outline("f", 0.2, 0.2, 0.3, 0.3, { floating: true })), dragged(), wide);
    assert.deepEqual(over.slot, { x: 0.5, y: 0, w: 0.5, h: 1 });
    const fws = W.dropPreview(entryOf(outline("f", 0, 0, 0.5, 0.5, { floating: true, floatSpace: true }), outline("t", 0, 0, 1, 1, { floatSpace: true })), dragged({ floating: true }), wide);
    assert.equal(fws.tile, false);
});

// ---- thumbnails show the usable area ----
const withBar = {
    1: { id: 1, name: "DP-3", workspaceId: 11, x: 0, y: 0, w: 1536, h: 864, reserved: [0, 26, 0, 0] }
};

test("a tiled window fills the whole thumbnail: the bar and the edge gap are left out", () => {
    const [strip] = W.screens([win(11, 1, [2, 28], [1532, 834], { address: "t" })], withBar, 11, "", 2);
    const w = strip.entries[0].windows[0];
    assert.deepEqual([w.x, w.y, w.w, w.h], [0, 0, 1, 1]);
});

test("the strip's aspect is the usable area's", () => {
    const [strip] = W.screens([], withBar, 11, "", 2);
    assert.ok(Math.abs(strip.aspect - 1532 / 834) < 1e-9);
});

test("without reserved areas or an inset the whole monitor is used", () => {
    const [strip] = W.screens([], { 1: showing[1] }, 11, "");
    assert.ok(Math.abs(strip.aspect - 1536 / 864) < 1e-9);
});
