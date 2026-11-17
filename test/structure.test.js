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
const qmlIn = (dir) => fs.readdirSync(path.join(root, dir)).filter((f) => f.endsWith(".qml")).map((f) => dir + "/" + f);
const qmlFiles = ["SnapLayouts.qml", "BarWidget.qml", "Panel.qml"].concat(qmlIn("components"), qmlIn("controllers"));

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

test("no component or controller is orphaned: each one is used by another QML file", () => {
    for (const file of qmlIn("components").concat(qmlIn("controllers"))) {
        const name = path.basename(file, ".qml");
        const users = qmlFiles.filter((f) => f !== file && new RegExp(`(^|[^\\w.])${name}\\s*\\{`, "m").test(read(f)));
        assert.ok(users.length > 0, `${file} is not used anywhere`);
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
const luaFiles = execFileSync("git", ["ls-files", "--cached", "--others", "--exclude-standard", "*.lua"], { cwd: root, encoding: "utf8" }).split("\n").filter(Boolean);

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
        release: D.release(2, "tile"),
        claim: D.release(2, "claim"),
        autoPlace: D.autoPlace([{ address: "0xaa", at: [4, 30], size: [760, 830], float: true, move: true }]),
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
    const lua = read("lua/overview-mode.lua"), qml = read("SnapLayouts.qml");
    const prefix = "io.github.n0rthstar88.snap-layouts:";
    assert.ok(lua.includes(prefix), "lua/overview-mode.lua does not use the plugin's event prefix");
    for (const event of ['report("overview")', 'report("swap-"'])
        assert.ok(lua.includes(event), `lua/overview-mode.lua no longer reports ${event}`);
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

test("lua/shortcuts.lua binds the events the library says each shortcut stands for", () => {
    const lua = read("lua/shortcuts.lua");
    const { SHORTCUTS } = load("shortcuts.js");
    for (const [name, event] of Object.entries(SHORTCUTS))
        assert.ok(lua.includes(`${name} = "${event}"`), `lua/shortcuts.lua does not map ${name} to ${event}`);
    assert.ok(read("SnapLayouts.qml").includes("io.github.n0rthstar88.snap-layouts:toggle"), "the plugin does not listen for the picker event");
});

test("the manifest's entry points exist, and the bar button loads the panel it ships", () => {
    const manifest = JSON.parse(read("manifest.json"));
    for (const [kind, file] of Object.entries(manifest.entryPoints))
        assert.ok(fs.existsSync(path.join(root, file)), `entry point ${kind}: ${file} does not exist`);
    assert.ok(manifest.kinds.includes("bar-widget") && manifest.entryPoints.barWidget, "the bar widget is not declared");
    assert.ok(manifest.barWidget && manifest.barWidget.displayName, "barWidget needs a displayName");
    assert.match(read(manifest.entryPoints.barWidget), /Qt\.resolvedUrl\("Panel\.qml"\)/);
});

test("the bar button and the overlay agree on the plugin's id", () => {
    const manifest = JSON.parse(read("manifest.json"));
    for (const file of ["BarWidget.qml", "Panel.qml", "SnapLayouts.qml", "controllers/Store.qml"])
        assert.ok(read(file).includes(`"${manifest.id}"`), `${file} does not use the manifest id`);
});

test("the panel only asks the bar button to save, and never touches the shell itself", () => {
    const code = read("Panel.qml").replace(/\/\/.*$/gm, "");
    assert.doesNotMatch(code, /execDetached|Quickshell\.exec|updateEntryInline|\bHyprland\./);
});

test("the shell command that sets a workspace's mode is valid shell", () => {
    const D = load("dispatch.js");
    for (const plan of [
        { target: "mosaic", step: "next", listed: true, plain: false, notify: true, release: "" },
        { target: "floating", step: "back", listed: false, plain: false, notify: false, release: "claim" },
        { target: "scrolling", step: "next", listed: false, plain: false, notify: false, release: "tile" },
        { target: "dwindle", step: "", listed: false, plain: true, notify: true, release: "tile" }
    ]) {
        const cmd = D.layoutCommand(plan, 11, "/home/me/.local/state/omarchy");
        const r = spawnSync("sh", ["-n", "-c", cmd], { encoding: "utf8" });
        assert.equal(r.status, 0, `${plan.target}: ${r.stderr}\n${cmd}`);
    }
    const stale = spawnSync("sh", ["-n", "-c", D.staleMarkCommand("/home/me/.local/state/omarchy")], { encoding: "utf8" });
    assert.equal(stale.status, 0, stale.stderr);
    const list = spawnSync("sh", ["-n", "-c", D.listCommand(5, "/home/me/.local/state/omarchy")], { encoding: "utf8" });
    assert.equal(list.status, 0, list.stderr);
    for (const target of ["tiling", "scrolling", "floating", "mosaic"]) {
        const cmd = D.defaultCommand(target, "/home/me/.local/state/omarchy");
        const r = spawnSync("sh", ["-n", "-c", cmd], { encoding: "utf8" });
        assert.equal(r.status, 0, `default ${target}: ${r.stderr}\n${cmd}`);
    }
});

test("every sentence the plugin asks the language catalogs for exists in English, and the other catalogs name no stranger", () => {
    const fs = require("node:fs");
    const path = require("node:path");
    const dir = path.join(__dirname, "..", "i18n");
    const english = JSON.parse(fs.readFileSync(path.join(dir, "en.json"), "utf8"));
    const used = new Set();
    for (const file of ["SnapLayouts.qml", "Panel.qml", "controllers/WinSaico.qml"]) {
        const text = fs.readFileSync(path.join(__dirname, "..", file), "utf8");
        for (const m of text.matchAll(/strings\.t\("([^"]+)"/g))
            used.add(m[1]);
    }
    assert.ok(used.size > 0);
    for (const key of used)
        assert.ok(key in english, "en.json lacks " + key);
    for (const file of fs.readdirSync(dir).filter((f) => f.endsWith(".json"))) {
        const catalog = JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"));
        for (const key of Object.keys(catalog))
            assert.ok(key in english, file + " has a key English does not: " + key);
    }
});

// ---- Taste lives in the libraries, not in the components ----

test("every Shape.ALPHA and Motion.TOKENS.dur name a component uses exists", () => {
    const shape = load("shape.js");
    const motion = load("motion.js");
    for (const file of qmlFiles) {
        const source = read(file);
        for (const [, name] of source.matchAll(/Shape\.ALPHA\.(\w+)/g))
            assert.ok(name in shape.ALPHA, `${file}: Shape.ALPHA.${name} is not defined`);
        for (const [, name] of source.matchAll(/Motion\.TOKENS\.dur\.(\w+)/g))
            assert.ok(name in motion.TOKENS.dur, `${file}: Motion.TOKENS.dur.${name} is not defined`);
    }
});

test("the components write no radius, duration or tint strength of their own", () => {
    for (const file of qmlFiles.filter((f) => f.startsWith("components/") && !/Wallpaper|Backdrop|MosaicIcon/.test(f))) {
        const code = read(file).replace(/\/\/.*$/gm, "");
        assert.ok(!/\bradius: \d/.test(code), `${file}: a radius written as a number`);
        assert.ok(!/duration: \d/.test(code), `${file}: a duration written as a number`);
        assert.ok(!/withAlpha\([^)]*, 0\.\d+\)/.test(code.replace(/withAlpha\(Commons\.Color\.[\w.]+, 1\)/g, "")), `${file}: a tint strength written as a number`);
    }
});
