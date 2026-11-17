const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const path = require("node:path");

// lua/drag.lua runs inside Hyprland; here it runs with a plain Lua and a stub for `hl`
// that holds the windows and the pointer and records what the file sends. Skipped
// where there is no Lua.
const lua = ["luajit", "lua5.4", "lua"].find((bin) => spawnSync(bin, ["-v"]).status === 0);

test("the drag sensor: which window is dragged, what it sends, when it gives up", { skip: !lua && "no lua installed" }, () => {
    const result = spawnSync(lua, ["test/drag.lua"], { cwd: path.join(__dirname, ".."), encoding: "utf8" });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stdout, /ok/);
});
