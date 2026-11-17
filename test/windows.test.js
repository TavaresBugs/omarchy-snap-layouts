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

test("assist offers only the windows of the workspace being filled, most recent first", () => {
    const list = [
        win({ address: "a", workspace: { id: 12 }, focusHistoryID: 1 }),
        win({ address: "b", workspace: { id: 11 }, focusHistoryID: 3 }),
        win({ address: "c", workspace: { id: 11 }, focusHistoryID: 2 }),
        win({ address: "d", workspace: { id: 1 }, focusHistoryID: 0 })
    ];
    assert.deepEqual(W.forAssist(list, 11).map((w) => w.address), ["c", "b"]);
});

test("assist also offers windows minimized from this workspace, not from another", () => {
    const min = (address, from) => win({
        address, workspace: { id: -98, name: "special:minimized" }, tags: ["omarchy-minimized-from-" + from]
    });
    const out = W.forAssist([min("mine", 11), min("theirs", 12)], 11).map((w) => w.address);
    assert.deepEqual(out, ["mine"]);
});

test("assist does not modify the original list", () => {
    const list = [win({ address: "x", workspace: { id: 1 }, focusHistoryID: 2 }), win({ address: "y", workspace: { id: 1 }, focusHistoryID: 1 })];
    W.forAssist(list, 1);
    assert.equal(list[0].address, "x");
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

test("a window belongs to the workspace it is on", () => {
    assert.equal(W.belongsToWorkspace(win({ workspace: { id: 11 } }), 11), true);
    assert.equal(W.belongsToWorkspace(win({ workspace: { id: 1 } }), 11), false);
});

test("a minimized window belongs to the workspace it was minimized from", () => {
    const min = (tags) => win({ workspace: { id: -98, name: "special:minimized" }, tags });
    assert.equal(W.belongsToWorkspace(min(["omarchy-minimized-from-12"]), 12), true);
    assert.equal(W.belongsToWorkspace(min(["omarchy-minimized-from-12*"]), 12), true);
    assert.equal(W.belongsToWorkspace(min(["omarchy-minimized-from-12"]), 11), false);
    assert.equal(W.belongsToWorkspace(min([]), 12), false);
    assert.equal(W.belongsToWorkspace(min(undefined), 12), false);
});

test("workspace ids compare as numbers", () => {
    assert.equal(W.belongsToWorkspace(win({ workspace: { id: "11" } }), 11), true);
});

