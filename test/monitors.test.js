const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const M = load("monitors.js");

const ipc = (over) => Object.assign({
    id: 0, name: "DP-3", x: 0, y: 0, width: 1920, height: 1080, scale: 1.25, transform: 0,
    reserved: [0, 26, 0, 0], activeWorkspace: { id: 11 }
}, over);

test("pixels become logical pixels using the scale", () => {
    const m = M.fromIpc(ipc());
    assert.equal(m.w, 1536);
    assert.equal(m.h, 864);
    assert.equal(m.workspaceId, 11);
    assert.deepEqual(m.reserved, [0, 26, 0, 0]);
});

test("a rotated monitor swaps width and height", () => {
    const m = M.fromIpc(ipc({ transform: 1, scale: 1 }));
    assert.equal(m.w, 1080);
    assert.equal(m.h, 1920);
});

test("missing scale and reserved fall back to safe values", () => {
    const m = M.fromIpc(ipc({ scale: 0, reserved: undefined, activeWorkspace: undefined }));
    assert.equal(m.w, 1920);
    assert.deepEqual(m.reserved, [0, 0, 0, 0]);
    assert.equal(m.workspaceId, 1);
});

test("at() finds the monitor under a point", () => {
    const a = M.fromIpc(ipc());
    const b = M.fromIpc(ipc({ id: 1, name: "eDP-1", x: 1536, scale: 1.5 }));
    const all = [a, b];
    assert.equal(M.at(all, 100, 100).name, "DP-3");
    assert.equal(M.at(all, 1600, 100).name, "eDP-1");
    assert.equal(M.at(all, 9000, 100), null);
    // The right/bottom edge belongs to the next monitor, not this one.
    assert.equal(M.at(all, 1536, 10).name, "eDP-1");
});

test("byId() matches Hyprland's numeric id, as number or string", () => {
    const list = [ipc({ id: 0 }), ipc({ id: 1, name: "eDP-1" })];
    assert.equal(M.byId(list, 1).name, "eDP-1");
    assert.equal(M.byId(list, "0").name, "DP-3");
    assert.equal(M.byId(list, 7), null);
});
