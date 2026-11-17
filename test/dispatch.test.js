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

test("two windows can trade places", () => {
    const lua = D.swapWindows("0xaa", "0xbb");
    assert.match(lua, /window\.swap\(\{ target = 'address:0xbb', window = 'address:0xaa' \}\)/);
});

test("trading places needs two different valid addresses", () => {
    assert.equal(D.swapWindows("0xaa", "0xaa"), "");
    assert.equal(D.swapWindows("0xaa", "nope"), "");
    assert.equal(D.swapWindows("0x1'); os.execute('x", "0xbb"), "");
});

test("leaving the overview's submap only acts when it is the active one", () => {
    assert.match(D.LEAVE_OVERVIEW_MODE, /get_current_submap\(\):find\('\^snap_layouts_overview'\)/);
});

test("autoPlace floats a tiled window, then sizes and places it, and never takes the focus", () => {
    const lua = D.autoPlace([{ address: "0xabc", at: [4, 30], size: [762, 830], float: true, move: true }]);
    assert.match(lua, /float\(\{ action = 'on', window = 'address:0xabc' \}\)/);
    assert.match(lua, /resize\(\{ x = 762, y = 830, window = 'address:0xabc' \}\)/);
    assert.match(lua, /move\(\{ x = 4, y = 30, window = 'address:0xabc' \}\)/);
    assert.doesNotMatch(lua, /focus|bring_to_top/);
});

test("autoPlace leaves out windows already in place and does not float a floating one", () => {
    assert.equal(D.autoPlace([{ address: "0xabc", at: [4, 30], size: [10, 10], float: true, move: false }]), "");
    const lua = D.autoPlace([{ address: "0xabc", at: [4, 30], size: [10, 10], float: false, move: true }]);
    assert.doesNotMatch(lua, /float/);
});

test("autoPlace refuses anything that is not an address or a number", () => {
    assert.equal(D.autoPlace([{ address: "0x1'); os.exit() --", at: [0, 0], size: [1, 1], float: true, move: true }]), "");
    assert.equal(D.autoPlace([{ address: "0xabc", at: [0, "x"], size: [1, 1], float: true, move: true }]), "");
    assert.equal(D.autoPlace(null), "");
});

const plan = (extra) => Object.assign({ target: "mosaic", step: "", listed: true, plain: false, notify: true, release: "" }, extra);
const STATE = "/home/me/.local/state/omarchy";

test("layoutCommand records the lists first, then sets the mode, then announces", () => {
    const cmd = D.layoutCommand(plan({ target: "floating", step: "back", listed: false, plain: true, notify: true }), 11, STATE);
    assert.match(cmd, /omarchy-hyprland-workspace-layout-toggle back/);
    assert.ok(cmd.indexOf("snap-layouts-workspaces") < cmd.indexOf("layout-toggle") && cmd.indexOf("layout-toggle") < cmd.indexOf("notification-send"));
});

test("entering WinSaico from floating or scrolling sets tiling silently, so only the plugin's message shows", () => {
    const cmd = D.layoutCommand(plan({ step: "next" }), 11, STATE);
    assert.doesNotMatch(cmd, /layout-toggle/);
    assert.match(cmd, /hyprctl eval 'o\.workspace_mode\(\{ workspace = "11", mode = "dwindle" \}\)'/);
    assert.match(cmd, /workspace-layouts\/11\.lua/);
    assert.match(cmd, /= dwindle ]; then rm -f/, "back to following the default when it is tiling");
    assert.match(cmd, /Workspace layout set to WinSaico/);
    assert.ok(cmd.indexOf("snap-layouts-workspaces") < cmd.indexOf("hyprctl eval"), "the list comes before Omarchy changes the mode");
});

test("entering WinSaico from tiling presses nothing: the workspace already tiles", () => {
    const cmd = D.layoutCommand(plan(), 11, STATE);
    assert.doesNotMatch(cmd, /workspace_mode|layout-toggle/);
});

test("layoutCommand takes a workspace out of the list when it leaves mosaic, and says nothing if Omarchy does", () => {
    const cmd = D.layoutCommand(plan({ target: "scrolling", step: "next", listed: false, plain: false, notify: false, release: "tile" }), 11, STATE);
    assert.doesNotMatch(cmd, /echo 11/);
    assert.match(cmd, /grep -vx '11'/);
    assert.doesNotMatch(cmd, /notification-send/);
    assert.match(cmd, /layout-toggle next/);
});

test("layoutCommand with no key to press only touches the list and the notification", () => {
    const cmd = D.layoutCommand(plan(), 11, STATE);
    assert.doesNotMatch(cmd, /layout-toggle/);
});

test("layoutCommand refuses anything that is not a plain workspace, folder or plan", () => {
    assert.equal(D.layoutCommand(plan(), 0, STATE), "");
    assert.equal(D.layoutCommand(plan(), "11; rm -rf ~", STATE), "");
    assert.equal(D.layoutCommand(plan(), 11, "/tmp/x'; rm -rf ~ #"), "");
    assert.equal(D.layoutCommand(plan(), 11, "relative/dir"), "");
    assert.equal(D.layoutCommand(plan({ target: "win" }), 11, STATE), "");
    assert.equal(D.layoutCommand(null, 11, STATE), "");
});

test("release tiles the windows the plugin floated, or hands them to Omarchy's floating mode", () => {
    const tile = D.release(2, "tile");
    assert.match(tile, /hl\.get_windows\(\{ tag = 'snap-layouts-floated' \}\)/);
    assert.match(tile, /tonumber\(w\.workspace\.id\) == 2/);
    assert.match(tile, /tag = '-snap-layouts-floated'/);
    assert.match(tile, /action = 'off'/);
    const claim = D.release(2, "claim");
    assert.match(claim, /tag = '\+omarchy-mode-floated'/);
    assert.doesNotMatch(claim, /action = 'off'/);
    assert.equal(D.release(0, "tile"), "");
    assert.equal(D.release("2; os.exit()", "tile"), "");
    assert.equal(D.release(2, "x"), "");
});

test("leaving WinSaico gives the windows back before Omarchy changes the mode", () => {
    const cmd = D.layoutCommand(plan({ target: "scrolling", step: "next", listed: false, plain: false, notify: false, release: "tile" }), 11, STATE);
    assert.ok(cmd.indexOf("snap-layouts-floated") > 0 && cmd.indexOf("snap-layouts-floated") < cmd.indexOf("layout-toggle next"));
});

test("autoPlace tags the windows it floats, so leaving the mode can tell them from the rest", () => {
    assert.match(D.autoPlace([{ address: "0xaa", at: [4, 30], size: [760, 830], float: true, move: true }]), /tag = '\+snap-layouts-floated'/);
    assert.doesNotMatch(D.autoPlace([{ address: "0xaa", at: [4, 30], size: [760, 830], float: false, move: true }]), /tag/);
});

test("layoutCommand ends by asking the bar to read the layout again", () => {
    assert.ok(D.layoutCommand(plan(), 11, STATE).endsWith("omarchy-shell -q omarchy.workspaces refresh"));
});

test("layoutCommand keeps the list of workspaces set to plain tiling", () => {
    const toTiling = D.layoutCommand(plan({ target: "dwindle", step: "", listed: false, plain: true, release: "tile" }), 11, STATE);
    assert.match(toTiling, /snap-layouts-plain' 2>\/dev\/null; echo 11; /);
    assert.match(toTiling, /grep -vx '11' '[^']*snap-layouts-plain'/);
    const toMosaic = D.layoutCommand(plan(), 11, STATE);
    assert.match(toMosaic, /grep -vx '11' '[^']*snap-layouts-plain' 2>\/dev\/null; true;/);
});

test("defaultCommand sets Omarchy's default, and WinSaico is tiling plus the plugin's mark", () => {
    const mosaic = D.defaultCommand("mosaic", STATE);
    assert.match(mosaic, /printf 'mosaic\\n' > '[^']*snap-layouts-default'/);
    assert.match(mosaic, /omarchy-hyprland-workspace-layout-default dwindle/);
    assert.ok(mosaic.indexOf("layout-default dwindle") < mosaic.indexOf("printf 'mosaic"), "the mark is written after Omarchy's command");
    assert.match(mosaic, /Default layout set to WinSaico/);
    const tiling = D.defaultCommand("tiling", STATE);
    assert.match(tiling, /rm -f '[^']*snap-layouts-default'/);
    assert.match(tiling, /layout-default dwindle/);
    assert.match(D.defaultCommand("scrolling", STATE), /layout-default scrolling/);
    assert.match(D.defaultCommand("floating", STATE), /layout-default floating; rm -f '[^']*snap-layouts-default'/);
});

test("defaultCommand refuses a mode that is not one and a folder that is not plain", () => {
    assert.equal(D.defaultCommand("win", STATE), "");
    assert.equal(D.defaultCommand("mosaic", "relative"), "");
    assert.equal(D.defaultCommand("mosaic", "/tmp/x'; rm -rf ~ #"), "");
});

test("listCommand adds a workspace to the mosaic list and nothing else", () => {
    const cmd = D.listCommand(5, STATE);
    assert.match(cmd, /echo 5;/);
    assert.match(cmd, /snap-layouts-workspaces/);
    assert.doesNotMatch(cmd, /layout-toggle|layout-default|notification/);
    assert.equal(D.listCommand(0, STATE), "");
    assert.equal(D.listCommand("5; x", STATE), "");
    assert.equal(D.listCommand(5, "rel"), "");
});

test("staleMarkCommand drops the mark when Omarchy's default file is newer", () => {
    const cmd = D.staleMarkCommand(STATE);
    assert.match(cmd, /workspace-layouts\/default\.lua' -nt '[^']*snap-layouts-default'/);
    assert.match(cmd, /rm -f/);
    assert.equal(D.staleMarkCommand("rel"), "");
});

test("the placements go right after the mode change, before the message and the bar refresh", () => {
    const place = "hl.dispatch(hl.dsp.window.move({ x = 1, y = 2, window = 'address:0xabc' }))";
    const cmd = D.layoutCommand(plan({ step: "next" }), 11, STATE, place);
    const mode = cmd.indexOf("mode = \"dwindle\"");
    const placed = cmd.indexOf("hyprctl eval '" + place.replace(/'/g, "'\\''") + "'");
    assert.ok(mode > 0 && placed > mode, "placed after the mode");
    assert.ok(placed < cmd.indexOf("notification-send") || placed < cmd.indexOf("Workspace 11: mosaic"), "placed before the message");
    assert.ok(placed < cmd.indexOf("omarchy.workspaces refresh"), "placed before the bar refresh");
});

test("quote makes one safe shell word, whatever it holds", () => {
    assert.equal(D.quote("a b"), "'a b'");
    assert.equal(D.quote("it's"), "'it'\\''s'");
});

test("without placements the command is what it was", () => {
    const a = D.layoutCommand(plan({ step: "next" }), 11, STATE);
    const b = D.layoutCommand(plan({ step: "next" }), 11, STATE, "");
    assert.equal(a, b);
});

test("the announcement is the plugin's sentence in the user's language for its own mode, Omarchy's for the others", () => {
    const own = D.layoutCommand(plan({ step: "next" }), 11, STATE, "", { mosaic: "Layout definido como WinSaico" });
    assert.match(own, /'Layout definido como WinSaico' 2>/);
    const floating = D.layoutCommand(plan({ target: "floating", step: "", listed: false, plain: true, notify: true }), 11, STATE);
    assert.match(floating, /"\$\(omarchy-i18n layout\.workspaceFloating\)"/);
    assert.doesNotMatch(floating, /WinSaico/);
});

test("a sentence with an apostrophe or a quote cannot break out of the command", () => {
    const cmd = D.layoutCommand(plan({ step: "next" }), 11, STATE, "", { mosaic: "it's \"x\"; rm -rf ~" });
    assert.match(cmd, /'it'\\''s "x"; rm -rf ~' 2>/);
});

test("forgetCommand removes the three files the plugin keeps, and nothing else", () => {
    const cmd = D.forgetCommand(STATE);
    assert.equal(cmd.split("; ").length, 3);
    for (const name of ["snap-layouts-workspaces", "snap-layouts-plain", "snap-layouts-default"])
        assert.ok(cmd.includes(`rm -f '${STATE}/${name}'`), name);
    assert.doesNotMatch(cmd, /workspace-layouts/);
    assert.equal(D.forgetCommand("rel"), "");
});
