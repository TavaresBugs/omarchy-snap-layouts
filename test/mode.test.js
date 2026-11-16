const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const M = load("mode.js");

test("a workspace is in mosaic mode when Omarchy has it in tiling and the plugin lists it", () => {
    assert.equal(M.current("dwindle", [11], 11), "mosaic");
    assert.equal(M.current("dwindle", [11], 1), "dwindle");
    assert.equal(M.current("dwindle", [], 11), "dwindle");
});

test("only tiling can be mosaic: a listed workspace that Omarchy moved elsewhere is not", () => {
    assert.equal(M.current("floating", [11], 11), "floating");
    assert.equal(M.current("scrolling", [11], 11), "scrolling");
});

test("an unknown Omarchy mode counts as tiling", () => {
    assert.equal(M.current("", [], 3), "dwindle");
    assert.equal(M.current("nonsense", [3], 3), "mosaic", "an unknown mode is tiling, which a listed workspace turns into mosaic");
    assert.equal(M.current(undefined, null, 3), "dwindle");
});

test("Super+L walks tiling, scrolling, floating, mosaic and round again; Super+Alt+L the other way", () => {
    let mode = "dwindle";
    const seen = [];
    for (let i = 0; i < 5; i++) { mode = M.neighbour(mode, "next"); seen.push(mode); }
    assert.deepEqual(seen, ["scrolling", "floating", "mosaic", "dwindle", "scrolling"]);
    mode = "dwindle";
    const back = [];
    for (let i = 0; i < 5; i++) { mode = M.neighbour(mode, "back"); back.push(mode); }
    assert.deepEqual(back, ["mosaic", "floating", "scrolling", "dwindle", "mosaic"]);
});

test("omarchyStep is the one press of Omarchy's key that reaches the mode", () => {
    assert.equal(M.omarchyStep("floating", "dwindle"), "next");
    assert.equal(M.omarchyStep("scrolling", "dwindle"), "back");
    assert.equal(M.omarchyStep("dwindle", "floating"), "back");
    assert.equal(M.omarchyStep("scrolling", "floating"), "next");
    assert.equal(M.omarchyStep("dwindle", "scrolling"), "next");
    assert.equal(M.omarchyStep("floating", "scrolling"), "back");
});

test("omarchyStep does nothing when already there or for names that are not modes", () => {
    assert.equal(M.omarchyStep("dwindle", "dwindle"), "");
    assert.equal(M.omarchyStep("", "floating"), "");
    assert.equal(M.omarchyStep("dwindle", "mosaic"), "");
    assert.equal(M.omarchyStep("x; rm -rf ~", "floating"), "");
});

test("omarchyStep reaches every mode from every mode in one press", () => {
    const order = ["dwindle", "scrolling", "floating"];
    const press = (mode, step) => order[(order.indexOf(mode) + (step === "next" ? 1 : 2)) % 3];
    for (const from of order)
        for (const to of order)
            if (from !== to) assert.equal(press(from, M.omarchyStep(from, to)), to, `${from} -> ${to}`);
});

test("going to mosaic from tiling is only the plugin's own list, and the plugin says the mode", () => {
    assert.deepEqual(M.plan("dwindle", "mosaic", "dwindle"), { target: "mosaic", step: "", listed: true, plain: false, notify: true, release: "" });
});

test("going to mosaic from scrolling or floating takes one press to tiling, and the plugin says the mode", () => {
    assert.deepEqual(M.plan("scrolling", "mosaic", "scrolling"), { target: "mosaic", step: "back", listed: true, plain: false, notify: true, release: "" });
    assert.deepEqual(M.plan("floating", "mosaic", "floating"), { target: "mosaic", step: "next", listed: true, plain: false, notify: true, release: "" });
});

test("leaving mosaic to tiling presses nothing, says the mode, gives the windows back and is remembered as plain", () => {
    assert.deepEqual(M.plan("dwindle", "dwindle", "mosaic"), { target: "dwindle", step: "", listed: false, plain: true, notify: true, release: "tile" });
});

test("leaving mosaic to scrolling or floating presses Omarchy's key, which announces it", () => {
    assert.deepEqual(M.plan("dwindle", "scrolling", "mosaic"), { target: "scrolling", step: "next", listed: false, plain: false, notify: false, release: "tile" });
    assert.deepEqual(M.plan("dwindle", "floating", "mosaic"), { target: "floating", step: "back", listed: false, plain: false, notify: false, release: "claim" });
});

test("moving between Omarchy's own modes releases nothing", () => {
    assert.equal(M.plan("dwindle", "scrolling", "dwindle").release, "");
    assert.equal(M.plan("scrolling", "floating", "scrolling").release, "");
});

test("plan refuses a target that is not a mode", () => {
    assert.equal(M.plan("dwindle", "win"), null);
    assert.equal(M.plan("dwindle", ""), null);
});

test("every walk around the ring ends with the right press", () => {
    // From any mode, Super+L lands on the next mode of the ring.
    for (const from of ["dwindle", "scrolling", "floating", "mosaic"]) {
        const omarchy = from === "mosaic" ? "dwindle" : from;
        const target = M.neighbour(from, "next");
        const p = M.plan(omarchy, target, from);
        assert.equal(p.target, target);
        assert.equal(p.listed, target === "mosaic");
    }
});

test("parseList reads whole workspace numbers, one per line, once, in order", () => {
    assert.deepEqual(M.parseList("11\n3\n11\n\n x \n0\n-2\n1.5\n 7 \n"), [3, 7, 11]);
    assert.deepEqual(M.parseList(""), []);
    assert.deepEqual(M.parseList(null), []);
});

test("with WinSaico as the default layout, a tiling workspace is mosaic unless set to plain tiling", () => {
    const d = { defaultMosaic: true, plain: [4] };
    assert.equal(M.current("dwindle", [], 2, d), "mosaic");
    assert.equal(M.current("dwindle", [], 4, d), "dwindle");
    assert.equal(M.current("dwindle", [4], 4, d), "mosaic", "the plugin's own list still wins");
    assert.equal(M.current("floating", [], 2, d), "floating", "only tiling can be mosaic");
    assert.equal(M.current("scrolling", [], 2, d), "scrolling");
});

test("without the default, only the list makes a workspace mosaic", () => {
    assert.equal(M.current("dwindle", [], 2, { defaultMosaic: false, plain: [] }), "dwindle");
    assert.equal(M.current("dwindle", [], 2), "dwindle");
    assert.equal(M.isMosaic([2], 2, {}), true);
    assert.equal(M.isMosaic([], 2, { defaultMosaic: true }), true);
    assert.equal(M.isMosaic(null, 2, null), false);
});

test("choosing plain tiling is remembered, anything else forgets it", () => {
    assert.equal(M.plan("dwindle", "dwindle", "mosaic").plain, true);
    for (const target of ["scrolling", "floating", "mosaic"])
        assert.equal(M.plan("dwindle", target, "dwindle").plain, false, target);
});
