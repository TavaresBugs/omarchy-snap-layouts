const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const K = load("shortcuts.js");
const P = K.PLUGIN;

const bind = (modmask, key, description) => ({ modmask, key, description });
const mine = (name, spec, modmask, key) => bind(modmask, key, K.tag(name, spec));

test("shortcuts are parsed into Hyprland's modifier mask and key", () => {
    assert.deepEqual(K.parse("SUPER + Z"), { modmask: 64, key: "Z" });
    assert.deepEqual(K.parse("ALT + TAB"), { modmask: 8, key: "TAB" });
    assert.deepEqual(K.parse("SUPER + SHIFT + CTRL + P"), { modmask: 69, key: "P" });
    assert.deepEqual(K.parse("F9"), { modmask: 0, key: "F9" });
    assert.deepEqual(K.parse("super+alt+f1"), { modmask: 72, key: "f1" });
    assert.deepEqual(K.parse("SUPER + code:34"), { modmask: 64, key: "code:34" });
});

test("things that are not shortcuts are rejected", () => {
    for (const bad of ["", "   ", "HYPER + Z", "SUPER +", "SUPER + Z Z", "SUPER + 'x", 3, null, undefined])
        assert.equal(K.valid(bad), false, String(bad));
});

test("a free shortcut is added", () => {
    const p = K.plan([bind(64, "Q", "Close window")], { picker: "SUPER + Z", overview: "" });
    assert.deepEqual(p.add, { picker: "SUPER + Z" });
    assert.equal(p.reload, false);
    assert.deepEqual(p.skipped, []);
});

test("a shortcut the plugin already bound is left alone", () => {
    const p = K.plan([mine("picker", "SUPER + Z", 64, "Z")], { picker: "SUPER + Z", overview: "" });
    assert.deepEqual(p.add, {});
    assert.equal(p.reload, false);
});

test("a shortcut set on purpose takes the keys, and says what it replaces", () => {
    const binds = [bind(8, "TAB", "Focus on next window"), bind(8, "TAB", "Visão geral das janelas"), bind(64, "Q", "Close")];
    const p = K.plan(binds, { picker: "", overview: "ALT + TAB" });
    assert.deepEqual(p.add, { overview: "ALT + TAB" });
    assert.deepEqual(p.replace, { overview: ["Focus on next window", "Visão geral das janelas"] });
    assert.equal(p.reload, false);
});

test("free keys replace nothing", () => {
    const p = K.plan([bind(64, "Q", "Close")], { picker: "SUPER + Z", overview: "" });
    assert.deepEqual(p.replace, {});
});

test("keys are compared without regard to case", () => {
    const p = K.plan([bind(64, "z", "Zoom")], { picker: "SUPER + Z", overview: "" });
    assert.deepEqual(p.add, { picker: "SUPER + Z" });
    assert.deepEqual(p.replace, { picker: ["Zoom"] });
});

test("changing a shortcut needs a reload and adds nothing meanwhile", () => {
    const p = K.plan([mine("overview", "ALT + TAB", 8, "TAB")], { picker: "", overview: "SUPER + TAB" });
    assert.equal(p.reload, true);
    assert.deepEqual(p.add, {});
});

test("dropping a shortcut also needs a reload", () => {
    const p = K.plan([mine("picker", "SUPER + Z", 64, "Z")], { picker: "", overview: "" });
    assert.equal(p.reload, true);
});

test("one shortcut staying put does not hide another that needs binding", () => {
    const binds = [mine("picker", "SUPER + Z", 64, "Z"), bind(8, "TAB", "Other")];
    const p = K.plan(binds, { picker: "SUPER + Z", overview: "ALT + TAB" });
    assert.deepEqual(p.add, { overview: "ALT + TAB" });
    assert.deepEqual(p.replace, { overview: ["Other"] });
    assert.equal(p.reload, false);
});

test("an invalid shortcut is reported, not bound", () => {
    const p = K.plan([], { picker: "HYPER + Z", overview: "" });
    assert.deepEqual(p.add, {});
    assert.equal(p.skipped[0].reason, "not a valid shortcut");
});

test("the plugin's own drag binds are never mistaken for a holder", () => {
    const p = K.plan([bind(0, "mouse:272", P + " drag")], { picker: "mouse:272", overview: "" });
    assert.deepEqual(p.add, { picker: "mouse:272" });
    assert.deepEqual(p.replace, {});
});

test("the Lua assignment carries valid shortcuts, quoted, and which ones replace others", () => {
    assert.equal(K.assignLua({ picker: "SUPER + Z", overview: "ALT + TAB" }, { overview: ["x"] }),
        'snap_layouts_shortcuts = { picker = "SUPER + Z", overview = "ALT + TAB" }; snap_layouts_shortcuts_replace = { overview = true }');
    assert.equal(K.assignLua({ picker: "HYPER + Z", bogus: "SUPER + Q" }, {}),
        "snap_layouts_shortcuts = {  }; snap_layouts_shortcuts_replace = {  }");
});

test("each shortcut maps to an event the plugin handles", () => {
    assert.deepEqual(K.SHORTCUTS, { picker: "toggle", overview: "overview" });
});
