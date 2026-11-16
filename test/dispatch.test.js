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

test("a window can be tiled on arrival", () => {
    assert.match(D.moveToWorkspace("0xabc", 3, "", true), /float\(\{ action = 'off'.*address:0xabc/);
    assert.doesNotMatch(D.moveToWorkspace("0xabc", 3, "", false), /float/);
    const lua = D.moveToWorkspace("0xabc", 4, "eDP-1", true);
    assert.ok(lua.indexOf("float") > lua.indexOf("window.move"));
});

test("swapping two workspaces goes through a free number", () => {
    const lua = D.swapWorkspaces(1, 2);
    assert.match(lua, /change_id\(\{ workspace = '1', id = 100001 \}\)/);
    assert.match(lua, /workspace = '2', id = 1 /);
    assert.match(lua, /workspace = '100001', id = 2 /);
    assert.match(lua, /elseif a then/);
});

test("swapping needs two different positive whole numbers", () => {
    assert.equal(D.swapWorkspaces(1, 1), "");
    assert.equal(D.swapWorkspaces(0, 2), "");
    assert.equal(D.swapWorkspaces(1.5, 2), "");
    assert.equal(D.swapWorkspaces("1); os.execute('x", 2), "");
});

test("going to a workspace uses Omarchy's slot on the owner monitor, or plain focus", () => {
    assert.match(D.goToWorkspace(13, 3, "DP-3"), /o\.workspaces\.focus\(3, 'DP-3'\)/);
    assert.equal(D.goToWorkspace(13, 3, ""), "hl.dispatch(hl.dsp.focus({ workspace = '13' }))");
    assert.equal(D.goToWorkspace(0, 3, "DP-3"), "");
    assert.equal(D.goToWorkspace(13, 3, "x'); evil('"), "hl.dispatch(hl.dsp.focus({ workspace = '13' }))");
});
