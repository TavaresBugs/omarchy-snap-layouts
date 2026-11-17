const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const H = load("hyprctl.js");

test("each answer is parsed on its own", () => {
    const text = '[{"a":1}]' + H.SEPARATOR + '{"b":2}' + H.SEPARATOR + "7";
    assert.deepEqual(H.parseSections(text), [[{ a: 1 }], { b: 2 }, 7]);
});

test("an answer that is not JSON is null and the others survive", () => {
    assert.deepEqual(H.parseSections("[1]" + H.SEPARATOR + "oops" + H.SEPARATOR + ""), [[1], null, null]);
});
