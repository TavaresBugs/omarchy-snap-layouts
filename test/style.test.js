const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const S = load("style.js");

test("reads ints and css lists as Hyprland reports them", () => {
    const style = S.resolve({ css: "3 2 2 2" }, { int: 2 });
    assert.deepEqual(style, { outer: 3, border: 2 });
});

test("floats are rounded", () => {
    assert.equal(S.resolve({ float: 2.6 }, null).outer, 3);
});

test("missing or unreadable answers fall back to the defaults", () => {
    assert.deepEqual(S.resolve(null, null), S.FALLBACK);
    assert.deepEqual(S.resolve({ css: "" }, { int: "wide" }), S.FALLBACK);
    assert.deepEqual(S.resolve({ css: "x y" }, undefined), S.FALLBACK);
    assert.deepEqual(S.resolve({ int: -3 }, {}), S.FALLBACK);
});

test("zero is a real value, not a missing one", () => {
    assert.equal(S.resolve({ css: "0 0 0 0" }, { int: 0 }).outer, 0);
});
