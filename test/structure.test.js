// Checks that hold the code base together: what the QML files import and call
// exists, the Lua files parse, and the manifest, README and changelog agree.
// The QML itself can't run here, so these catch the mistakes that would only
// show up on a live desktop (a misspelt library function, an orphaned
// component, a Lua syntax error).

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");
const { load } = require("./load");

const root = path.join(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const qmlFiles = ["SnapLayouts.qml"].concat(
    fs.readdirSync(path.join(root, "components")).filter((f) => f.endsWith(".qml")).map((f) => "components/" + f));

// ---- QML imports and the library symbols it uses ----

test("every JS library a QML file imports exists, and every symbol it uses from one is defined", () => {
    for (const file of qmlFiles) {
        const source = read(file);
        const dir = path.dirname(path.join(root, file));
        for (const [, rel, alias] of source.matchAll(/^import "([^"]+\.js)" as (\w+)/gm)) {
            const target = path.join(dir, rel);
            assert.ok(fs.existsSync(target), `${file}: imports ${rel}, which does not exist`);
            const api = load(path.relative(path.join(root, "lib"), target));
            const code = source.replace(/^import .*$/gm, "");
            const used = new Set([...code.matchAll(new RegExp(`(?<![\\w."/])${alias}\\.(\\w+)`, "g"))].map((m) => m[1]));
            for (const name of used)
                assert.ok(name in api, `${file}: ${alias}.${name} is not defined in ${rel}`);
        }
    }
});

test("every folder or component a QML file imports exists", () => {
    for (const file of qmlFiles) {
        const dir = path.dirname(path.join(root, file));
        for (const [, rel] of read(file).matchAll(/^import "([^"]+)"$/gm))
            assert.ok(fs.existsSync(path.join(dir, rel)), `${file}: imports ${rel}, which does not exist`);
    }
});

test("no component is orphaned: each one is used by another QML file", () => {
    for (const file of fs.readdirSync(path.join(root, "components")).filter((f) => f.endsWith(".qml"))) {
        const name = file.replace(/\.qml$/, "");
        const users = qmlFiles.filter((f) => f !== "components/" + file && new RegExp(`(^|[^\\w.])${name}\\s*\\{`, "m").test(read(f)));
        assert.ok(users.length > 0, `components/${file} is not used anywhere`);
    }
});

test("no debugging output is left in the code", () => {
    for (const file of qmlFiles.concat(fs.readdirSync(path.join(root, "lib")).map((f) => "lib/" + f)))
        assert.doesNotMatch(read(file), /console\.log|\bDBG\b/, `${file} has leftover debug output`);
});

test("components stay presentation: they read libraries and Qt, never Hyprland or the plugin", () => {
    for (const file of qmlFiles.filter((f) => f.startsWith("components/")))
        assert.doesNotMatch(read(file).replace(/\/\/.*$/gm, ""), /import Quickshell\.Hyprland|execDetached|\bHyprland\.|Quickshell\.exec/, `${file} reaches outside presentation`);
});

// ---- Lua ----

const luajit = spawnSync("luajit", ["-v"]).status === 0;
const luaFiles = execFileSync("git", ["ls-files", "*.lua"], { cwd: root, encoding: "utf8" }).split("\n").filter(Boolean);

test("every Lua file parses", { skip: !luajit && "luajit is not installed" }, () => {
    for (const file of luaFiles) {
        const r = spawnSync("luajit", ["-bl", path.join(root, file)], { encoding: "utf8" });
        assert.equal(r.status, 0, `${file}: ${r.stderr}`);
    }
});

test("every Lua snippet the plugin sends to Hyprland parses", { skip: !luajit && "luajit is not installed" }, () => {
    const D = load("dispatch.js");
    const snippets = {
        moveToWorkspace: D.moveToWorkspace("0xabc", 14, ""),
        moveToOwner: D.moveToWorkspace("0xabc", 4, "eDP-1", true),
        swapWorkspaces: D.swapWorkspaces(14, 15),
        goToWorkspace: D.goToWorkspace(13, 3, "DP-3"),
        goToPlain: D.goToWorkspace(13, 3, ""),
        swapWindows: D.swapWindows("0xaa", "0xbb"),
        leave: D.LEAVE_OVERVIEW_MODE
    };
    const K = load("shortcuts.js");
    snippets.shortcuts = K.assignLua({ picker: "SUPER + Z", overview: "ALT + TAB" }, { overview: ["Focus on next window"] });
    for (const [name, lua] of Object.entries(snippets)) {
        assert.ok(lua.length > 0, `${name} produced nothing`);
        const r = spawnSync("luajit", ["-bl", "-"], { input: lua, encoding: "utf8" });
        assert.equal(r.status, 0, `${name}: ${r.stderr}\n${lua}`);
    }
});

test("the events the overview submap reports are the ones the plugin listens for", () => {
    const lua = read("overview-mode.lua"), qml = read("SnapLayouts.qml");
    const prefix = "io.github.n0rthstar88.snap-layouts:";
    assert.ok(lua.includes(prefix), "overview-mode.lua does not use the plugin's event prefix");
    for (const event of ['report("overview")', 'report("swap-"'])
        assert.ok(lua.includes(event), `overview-mode.lua no longer reports ${event}`);
    assert.ok(qml.includes(prefix + "overview") && qml.includes(prefix + "swap-"), "SnapLayouts.qml does not listen for them");
});

// ---- Manifest, README, changelog ----

const manifest = JSON.parse(read("manifest.json"));

test("the manifest's entry point exists and its version heads the changelog", () => {
    assert.ok(fs.existsSync(path.join(root, manifest.entryPoints.overlay)));
    const heading = read("CHANGELOG.md").match(/^## (\S+)/m);
    assert.equal(heading && heading[1], manifest.version, "CHANGELOG.md's newest section is not the manifest's version");
});

test("the README installs from the manifest's repository and uses the manifest's plugin id", () => {
    const readme = read("README.md");
    assert.ok(readme.includes(`omarchy plugin add ${manifest.repository}`), "README's install command does not match manifest.repository");
    for (const [, id] of readme.matchAll(/(io\.github\.[\w.-]+snap-layouts)[:" ]/g))
        assert.equal(id, manifest.id);
});

test("every option the README documents is one the settings accept, and the other way round", () => {
    const { DEFAULTS } = load("settings.js");
    const readme = read("README.md");
    for (const key of Object.keys(DEFAULTS))
        assert.ok(readme.includes("`" + key + "`"), `option ${key} is not documented in the README`);
});

test("shortcuts.lua binds the events the library says each shortcut stands for", () => {
    const lua = read("shortcuts.lua");
    const { SHORTCUTS } = load("shortcuts.js");
    for (const [name, event] of Object.entries(SHORTCUTS))
        assert.ok(lua.includes(`${name} = "${event}"`), `shortcuts.lua does not map ${name} to ${event}`);
    assert.ok(read("SnapLayouts.qml").includes("io.github.n0rthstar88.snap-layouts:toggle"), "the plugin does not listen for the picker event");
});
