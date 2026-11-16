const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const A = load("autosnap.js");
const L = load("layouts.js");

const monitor = { x: 0, y: 0, w: 1536, h: 864, reserved: [0, 26, 0, 0] };
const gaps = { outer: 2, inner: 0, border: 2 };

let n = 0;
// A window the plugin floated on workspace 3, by default.
function win(extra) {
    n++;
    return Object.assign({
        address: "0x" + n.toString(16),
        mapped: true, hidden: false, floating: true, fullscreen: 0, pinned: false,
        tags: ["snap-layouts-floated"],
        workspace: { id: 3, name: "3" }, at: [100, 100], size: [700, 500], focusHistoryID: n
    }, extra);
}

function plan(clients, extra) {
    return A.plan(Object.assign({ monitor, gaps, workspaceId: 3, clients, records: {}, nextSeq: 1 }, extra));
}

test("one window fills the usable area", () => {
    const { items } = plan([win()]);
    assert.equal(items.length, 1);
    assert.deepEqual(items[0].at, [4, 30]);
    assert.deepEqual(items[0].size, [1528, 830]);
    assert.equal(items[0].move, true);
});

test("the windows share the screen in the plugin's mosaic, the oldest in the first zone", () => {
    const a = win({ focusHistoryID: 5 }), b = win({ focusHistoryID: 4 }), c = win({ focusHistoryID: 3 }), d = win({ focusHistoryID: 2 });
    const { items } = plan([d, c, b, a]);
    assert.deepEqual(items.map((i) => i.address), [a.address, b.address, c.address, d.address]);
    const zones = L.mosaicZones(4);
    items.forEach((item, i) => {
        const r = L.zoneRect(monitor, gaps, zones[i]);
        assert.deepEqual(item.at, [r.x, r.y]);
        assert.deepEqual(item.size, [r.w, r.h]);
    });
});

test("eight windows are eight even tiles", () => {
    const clients = [];
    for (let i = 0; i < 8; i++) clients.push(win({ focusHistoryID: 20 - i }));
    const { items } = plan(clients);
    const areas = items.map((i) => i.size[0] * i.size[1]);
    assert.ok(Math.max(...areas) / Math.min(...areas) < 1.1);
});

test("windows already where the plan wants them are not moved again", () => {
    const first = plan([win()]).items[0];
    const w = win({ at: first.at, size: first.size });
    const second = plan([w], { records: { [w.address]: { seq: 1 } } });
    assert.equal(second.items[0].move, false);
});

test("a window that has joined goes back to its place even if it was moved or resized", () => {
    const w = win({ at: [400, 300], size: [500, 400] });
    const { items } = plan([w], { records: { [w.address]: { seq: 1 } } });
    assert.equal(items[0].move, true);
});

test("a window that floats on its own account stays out, unless the mode has just been switched on", () => {
    const dialog = win({ tags: [] });
    const app = win();
    assert.deepEqual(plan([dialog, app]).items.map((i) => i.address), [app.address]);
    assert.equal(plan([dialog, app], { adopt: true }).items.length, 2);
});

test("windows the plugin floated join, and a window floating on its own account does not", () => {
    const mine = win({ tags: ["snap-layouts-floated"] });
    const starred = win({ tags: ["snap-layouts-floated*"] });
    const dialog = win({ tags: [] });
    assert.equal(plan([mine, starred, dialog]).items.length, 2);
});

test("a tiled window on the workspace joins and is floated first", () => {
    const tiled = win({ floating: false, tags: [] });
    const { items } = plan([tiled]);
    assert.equal(items.length, 1);
    assert.equal(items[0].float, true);
    assert.equal(plan([win()]).items[0].float, false);
});

test("fullscreen, pinned, other workspaces and hidden windows are left out", () => {
    const clients = [win({ fullscreen: 2 }), win({ pinned: true }), win({ workspace: { id: 4, name: "4" } }), win({ hidden: true })];
    assert.deepEqual(plan(clients, { adopt: true }).items, []);
});

test("a new window goes last and the others keep their order", () => {
    const a = win(), b = win(), c = win();
    const records = { [a.address]: { seq: 5 }, [b.address]: { seq: 2 } };
    const { items } = plan([a, b, c], { records, newAddresses: [c.address] });
    assert.deepEqual(items.map((i) => i.address), [b.address, a.address, c.address]);
});

test("windows from before are ordered by how long ago they were used, oldest first", () => {
    const old = win({ focusHistoryID: 7 }), recent = win({ focusHistoryID: 1 });
    assert.deepEqual(plan([recent, old]).items.map((i) => i.address), [old.address, recent.address]);
});

test("several windows that opened together come after the older ones, in the order they were used", () => {
    const old = win();
    const x = win({ focusHistoryID: 1 }), y = win({ focusHistoryID: 0 });
    const { items } = plan([y, x, old], { records: { [old.address]: { seq: 4 } }, newAddresses: [x.address, y.address] });
    assert.deepEqual(items.map((i) => i.address), [old.address, x.address, y.address]);
});

test("a window's own area is the whole zone: WinSaico has no title bar", () => {
    const { items } = plan([win()]);
    assert.deepEqual(items[0].at, [4, 30]);
    assert.deepEqual(items[0].size, [1528, 830]);
});

test("keep floats the tiled windows of the workspace where they are, and nothing else", () => {
    const tiled = win({ floating: false, tags: [], at: [10, 20], size: [300, 400] });
    const floating = win({ tags: [] });
    const other = win({ floating: false, tags: [], workspace: { id: 4, name: "4" } });
    const full = win({ floating: false, tags: [], fullscreen: 2 });
    const items = A.keep(3, [tiled, floating, other, full]);
    assert.equal(items.length, 1);
    assert.deepEqual(items[0], { address: tiled.address, zone: 0, at: [10, 20], size: [300, 400], seq: 0, float: true, move: true });
    assert.deepEqual(A.keep(3, null), []);
});

test("each item carries the sequence number it keeps", () => {
    const a = win({ focusHistoryID: 2 }), b = win({ focusHistoryID: 1 });
    const { items, nextSeq } = plan([a, b], { nextSeq: 10 });
    assert.deepEqual(items.map((i) => i.seq), [10, 11]);
    assert.equal(nextSeq, 12);
    const kept = plan([a], { records: { [a.address]: { seq: 3 } }, nextSeq: 10 });
    assert.equal(kept.items[0].seq, 3);
    assert.equal(kept.nextSeq, 10);
});

test("nothing to do without windows", () => {
    assert.deepEqual(plan([]).items, []);
});
