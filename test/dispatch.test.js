const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const D = load("dispatch.js");

test("moving to a workspace is a silent window move", () => {
    const lua = D.moveToWorkspace("0xabc123", 14);
    assert.match(lua, /workspace = '14'/);
    assert.match(lua, /follow = false/);
    assert.match(lua, /address:0xabc123/);
});

test("with an owner monitor the workspace is created there and the view restored", () => {
    const lua = D.moveToWorkspace("0xabc123", 4, "eDP-1");
    assert.match(lua, /hl\.get_monitor\('eDP-1'\)/);
    assert.match(lua, /hl\.get_workspace\(4\)/);
    assert.match(lua, /set_workspace/);
    assert.match(lua, /focus\(\{ window/);
});

test("invalid addresses, ids and monitor names produce no code", () => {
    assert.equal(D.moveToWorkspace("0x1'); os.execute('x", 3), "");
    assert.equal(D.moveToWorkspace("nope", 3), "");
    assert.equal(D.moveToWorkspace("0x1", 0), "");
    assert.equal(D.moveToWorkspace("0x1", 2.5), "");
    assert.equal(D.moveToWorkspace("0x1", 3, "x'); evil('"), "");
});
