const test = require("node:test");
const assert = require("node:assert/strict");
const { load } = require("./load");

const M = load("menu.js");
const BLOCK = M.rows("Tiling", "WinSaico");
const parse = (text) => JSON.parse(M.strip(text));

const OMARCHY_TEMPLATE = `{
  // Extend the Quickshell Omarchy menu with JSONC.
  //
  // "personal": {"icon":"","label":"Personal"},
}
`;

test("the rows are Tiling, restated to need the mark absent, and WinSaico, which needs it", () => {
    const rows = parse("{\n" + BLOCK.join("\n") + "\n}");
    const tiling = rows["appearance.workspace-layout.dwindle"];
    const winsaico = rows["appearance.workspace-layout.mosaic"];
    assert.equal(tiling.label, "Tiling");
    assert.match(tiling.checked, /! -e/);
    assert.equal(tiling.action, "omarchy-hyprland-workspace-layout-default dwindle");
    assert.equal(winsaico.label, "WinSaico");
    assert.doesNotMatch(winsaico.checked, /! -e/);
    assert.equal(winsaico.action, "omarchy-shell snaplayouts defaultLayout winsaico");
});

test("the label is written as given, whatever is in it", () => {
    const rows = parse("{\n" + M.rows('Mosa"ico\\', "WinSaico").join("\n") + "\n}");
    assert.equal(rows["appearance.workspace-layout.dwindle"].label, 'Mosa"ico\\');
});

test("installing into Omarchy's empty template keeps its comments and adds the block", () => {
    const out = M.install(OMARCHY_TEMPLATE, BLOCK);
    assert.ok(M.hasBlock(out));
    assert.ok(out.includes("// Extend the Quickshell Omarchy menu"));
    assert.deepEqual(Object.keys(parse(out)), ["appearance.workspace-layout.dwindle", "appearance.workspace-layout.mosaic"]);
});

test("installing after other rows gives the last one its comma", () => {
    const text = '{\n  "personal": {"icon":"x","label":"Personal"},\n  "personal.notes": {"label":"Notes","action":"open https://example.com/a//b"}\n}\n';
    const out = M.install(text, BLOCK);
    const rows = parse(out);
    assert.equal(rows["personal.notes"].action, "open https://example.com/a//b");
    assert.equal(rows["appearance.workspace-layout.mosaic"].label, "WinSaico");
    assert.ok(out.includes('"open https://example.com/a//b"},\n'));
});

test("a file Omarchy itself could not read (a comment after a row) is left alone", () => {
    assert.equal(M.valid('{\n  "a": {"label":"A"} // mine\n}\n'), false);
    assert.equal(M.install('{\n  "a": {"label":"A"} // mine\n}\n', BLOCK), null);
});

test("a file with no braces at all (comments only, or empty) becomes an object", () => {
    for (const text of ["", "// nothing here\n"]) {
        const out = M.install(text, BLOCK);
        assert.equal(M.valid(out), true);
        assert.ok(M.hasBlock(out));
        assert.equal(Object.keys(parse(out)).length, 2);
    }
});

test("installing twice leaves one block", () => {
    const once = M.install(OMARCHY_TEMPLATE, BLOCK);
    const twice = M.install(once, M.rows("Mosaico", "WinSaico"));
    assert.equal(twice.split(">>> snap-layouts").length, 2);
    assert.equal(parse(twice)["appearance.workspace-layout.dwindle"].label, "Mosaico");
});

test("removing gives back what the file was", () => {
    const text = '{\n  // mine\n  "a": {"label":"A"}\n}\n';
    const out = M.remove(M.install(text, BLOCK));
    assert.equal(out, text);
    assert.equal(M.remove(M.install(OMARCHY_TEMPLATE, BLOCK)), OMARCHY_TEMPLATE);
});

test("removing leaves no comma dangling, and no block", () => {
    const out = M.remove(M.install('{\n  "a": {"label":"A"},\n  "b": {"label":"B"}\n}\n', BLOCK));
    assert.equal(M.hasBlock(out), false);
    assert.doesNotMatch(out, /,\s*\}/);
    assert.deepEqual(Object.keys(parse(out)), ["a", "b"]);
});

test("rows from a hand-made install of the extras are taken over", () => {
    const legacy = '{\n  // WinSaico (Snap Layouts plugin): see extras/menu/omarchy-menu.jsonc in the plugin repo.\n'
        + '  "appearance.workspace-layout.dwindle": {"icon":"x","label":"Mosaico","checked":"[[ -e snap-layouts-default ]]","action":"a"},\n'
        + '  "appearance.workspace-layout.mosaic": {"icon":"y","iconFont":"SnapLayouts Icons","label":"WinSaico","checked":"[[ -e snap-layouts-default ]]","action":"b"}\n}\n';
    const out = M.install(legacy, BLOCK);
    assert.equal(out.split("appearance.workspace-layout.mosaic").length, 2);
    assert.equal(out.includes("iconFont"), false);
    assert.equal(parse(M.remove(legacy)) && Object.keys(parse(M.remove(legacy))).length, 0);
});

test("a file that is not a menu is left alone", () => {
    assert.equal(M.install("[1, 2]", BLOCK), null);
    assert.equal(M.install('{ "a": ', BLOCK), null);
    assert.equal(M.install('{ "a": {} } trailing', BLOCK), null);
});

test("valid reads a menu the way Omarchy does", () => {
    assert.equal(M.valid(""), true);
    assert.equal(M.valid("// only comments"), true);
    assert.equal(M.valid('{ "a": {"x": 1,}, }'), true);
    assert.equal(M.valid("{ nope"), false);
    assert.equal(M.valid("[]"), false);
});

test("syncing writes the block when WinSaico is on, and nothing when the file already has it", () => {
    const first = M.sync(OMARCHY_TEMPLATE, BLOCK);
    assert.ok(M.hasBlock(first));
    assert.equal(M.sync(first, BLOCK), null);
    // a changed label (the language was switched) is written again
    const relabelled = M.sync(first, M.rows("Mosaico", "WinSaico"));
    assert.equal(parse(relabelled)["appearance.workspace-layout.dwindle"].label, "Mosaico");
});

test("syncing takes the block out when WinSaico is off, and leaves a clean file be", () => {
    const first = M.sync(OMARCHY_TEMPLATE, BLOCK);
    assert.equal(M.sync(first, null), OMARCHY_TEMPLATE);
    assert.equal(M.sync(OMARCHY_TEMPLATE, null), null);
    assert.equal(M.sync("", null), null);
});

test("syncing leaves a file it cannot edit alone", () => {
    assert.equal(M.sync("{ nope", BLOCK), null);
});

test("rows a block already holds do not move when the user adds their own after them", () => {
    const first = M.sync(OMARCHY_TEMPLATE, BLOCK);
    const edited = first.replace(/\}\n$/, '  ,"mine": {"label":"Mine"}\n}\n');
    assert.equal(M.sync(edited, BLOCK), null);
});
