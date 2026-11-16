const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const W = load("windows.js");

const win = (over) => Object.assign({
    address: "0x1", mapped: true, hidden: false, floating: false, pinned: false, fullscreen: 0,
    workspace: { id: 11, name: "11" }, at: [4, 30], size: [760, 830], focusHistoryID: 0
}, over);

test("isSnappable: normal workspaces and the minimized one only", () => {
    assert.equal(W.isSnappable(win()), true);
    assert.equal(W.isSnappable(win({ workspace: { id: -98, name: "special:minimized" } })), true);
    assert.equal(W.isSnappable(win({ workspace: { id: -99, name: "special:magic" } })), false);
    assert.equal(W.isSnappable(win({ mapped: false })), false);
    assert.equal(W.isSnappable(win({ hidden: true })), false);
    assert.equal(W.isSnappable(win({ address: "" })), false);
    assert.equal(W.isSnappable(null), false);
});

test("assist order: current workspace first, then most recent", () => {
    const list = [
        win({ address: "a", workspace: { id: 1 }, focusHistoryID: 1 }),
        win({ address: "b", workspace: { id: 11 }, focusHistoryID: 3 }),
        win({ address: "c", workspace: { id: 11 }, focusHistoryID: 2 })
    ];
    assert.deepEqual(W.sortForAssist(list, 11).map((w) => w.address), ["c", "b", "a"]);
});

test("overview order: by workspace, minimized last, then most recent", () => {
    const list = [
        win({ address: "min", workspace: { id: -98, name: "special:minimized" }, focusHistoryID: 0 }),
        win({ address: "w11b", workspace: { id: 11 }, focusHistoryID: 5 }),
        win({ address: "w1", workspace: { id: 1 }, focusHistoryID: 9 }),
        win({ address: "w11a", workspace: { id: 11 }, focusHistoryID: 2 })
    ];
    assert.deepEqual(W.sortForOverview(list).map((w) => w.address), ["w1", "w11a", "w11b", "min"]);
});

test("sorting does not modify the original list", () => {
    const list = [win({ address: "x", focusHistoryID: 2 }), win({ address: "y", focusHistoryID: 1 })];
    W.sortForOverview(list);
    assert.equal(list[0].address, "x");
});

test("Alt+Tab starts on the previously used window", () => {
    const list = [
        win({ address: "current", focusHistoryID: 0 }),
        win({ address: "old", focusHistoryID: 4 }),
        win({ address: "previous", focusHistoryID: 1 })
    ];
    assert.equal(W.previousWindowIndex(list), 2);
    assert.equal(W.previousWindowIndex([win({ focusHistoryID: 0 })]), 0);
    assert.equal(W.previousWindowIndex([]), 0);
});

test("positionsOf keys position and size by address", () => {
    const p = W.positionsOf([win({ address: "a", at: [1, 2], size: [3, 4] })]);
    assert.deepEqual(p.a, { at: [1, 2], size: [3, 4] });
    assert.deepEqual(W.positionsOf(null), {});
});

// The case that started this: MetaTrader tiled full-screen, hidden under two
// floating windows (Claude on the left, Firefox on the right).
const metatrader = win({ address: "mt", floating: false, at: [4, 30], size: [1528, 830] });
const claude = win({ address: "claude", floating: true, at: [4, 30], size: [762, 830] });
const firefox = win({ address: "firefox", floating: true, at: [770, 30], size: [762, 830] });

test("floating windows over a tiled one are reported", () => {
    assert.deepEqual(W.floatsCovering(metatrader, [metatrader, claude, firefox]), ["claude", "firefox"]);
});

test("floating windows that do not overlap are left alone", () => {
    const far = win({ address: "far", floating: true, at: [3000, 30], size: [400, 400] });
    assert.deepEqual(W.floatsCovering(metatrader, [metatrader, far]), []);
});

test("only the target's workspace counts", () => {
    const other = win({ address: "o", floating: true, workspace: { id: 1 }, at: [4, 30], size: [500, 500] });
    assert.deepEqual(W.floatsCovering(metatrader, [metatrader, other]), []);
});

test("pinned and fullscreen floats are never touched", () => {
    const pinned = win({ address: "p", floating: true, pinned: true });
    const full = win({ address: "f", floating: true, fullscreen: 1 });
    assert.deepEqual(W.floatsCovering(metatrader, [metatrader, pinned, full]), []);
});

test("a floating target has nothing covering it that needs tiling", () => {
    assert.deepEqual(W.floatsCovering(claude, [metatrader, claude, firefox]), []);
});

test("minimized or special targets are not handled here", () => {
    const min = win({ address: "m", workspace: { id: -98, name: "special:minimized" } });
    assert.deepEqual(W.floatsCovering(min, [min, claude]), []);
    assert.deepEqual(W.floatsCovering(null, [claude]), []);
});
