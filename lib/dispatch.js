.pragma library

// Lua snippets for `hyprctl eval`. Everything interpolated into them is
// validated here, so a odd value can never turn into code.

function validAddress(address) {
    return /^0x[0-9a-fA-F]+$/.test(String(address));
}

function validMonitor(name) {
    return /^[A-Za-z0-9._:-]+$/.test(String(name));
}

// Send a window to a workspace without following it. `monitorName` is the
// monitor that owns the workspace. A workspace that is empty does not exist
// yet, and Hyprland would create it on the window's own monitor; so it is
// created on the owner by showing it there for a moment, and the owner's
// previous workspace and the focused window are put back. Returns "" when the
// arguments are not valid. With `tile`, a floating window is tiled on arrival.
function moveToWorkspace(address, workspaceId, monitorName, tile) {
    var id = Number(workspaceId);
    if (!validAddress(address) || !(id > 0) || Math.floor(id) !== id)
        return "";
    var move = "hl.dispatch(hl.dsp.window.move({ workspace = '" + id + "', follow = false, window = 'address:" + address + "' }))";
    if (tile)
        move += " hl.dispatch(hl.dsp.window.float({ action = 'off', window = 'address:" + address + "' }))";
    if (!monitorName)
        return move;
    if (!validMonitor(monitorName))
        return "";
    return [
        "local mon = hl.get_monitor('" + monitorName + "')",
        "if hl.get_workspace(" + id + ") or not mon then " + move + " else",
        "local prev = mon.active_workspace and mon.active_workspace.id",
        "local active = hl.get_active_window()",
        "hl.dispatch(hl.dsp.focus({ monitor = mon.name }))",
        "hl.dispatch(hl.dsp.focus({ workspace = '" + id + "' }))",
        move,
        "if prev and hl.get_workspace(prev) then mon:set_workspace({ workspace = tostring(prev) })",
        "elseif prev then hl.dispatch(hl.dsp.focus({ workspace = tostring(prev) })) end",
        "if active then hl.dispatch(hl.dsp.focus({ window = 'address:' .. active.address })) end",
        "end"
    ].join(" ");
}

// Make two workspaces trade places: each keeps its windows and takes the
// other's number. A workspace that does not exist yet is just renumbered
// into. Hyprland needs a free number in between, hence the third step.
function swapWorkspaces(a, b) {
    var x = Number(a), y = Number(b);
    if (!(x > 0) || !(y > 0) || Math.floor(x) !== x || Math.floor(y) !== y || x === y)
        return "";
    var tmp = 100000 + x;
    function renumber(from, to) {
        return "hl.dispatch(hl.dsp.workspace.change_id({ workspace = '" + from + "', id = " + to + " }))";
    }
    return [
        "local a, b = hl.get_workspace(" + x + "), hl.get_workspace(" + y + ")",
        "if a and b then " + renumber(x, tmp) + " " + renumber(y, x) + " " + renumber(tmp, y),
        "elseif a then " + renumber(x, y),
        "elseif b then " + renumber(y, x) + " end"
    ].join(" ");
}

// Go to a workspace of the monitor that owns it, the way Omarchy's own keys do
// (its slot on that monitor). Without the owner, plain focus.
function goToWorkspace(workspaceId, slot, monitorName) {
    var id = Number(workspaceId), s = Number(slot);
    if (!(id > 0) || Math.floor(id) !== id)
        return "";
    var plain = "hl.dispatch(hl.dsp.focus({ workspace = '" + id + "' }))";
    if (!monitorName || !(s > 0) || !validMonitor(monitorName))
        return plain;
    return "if o and o.workspaces then hl.dispatch(o.workspaces.focus(" + s + ", '" + monitorName + "')) else " + plain + " end";
}

// Make two tiled windows trade places in the layout.
function swapWindows(a, b) {
    if (!validAddress(a) || !validAddress(b) || a === b)
        return "";
    return "hl.dispatch(hl.dsp.window.swap({ target = 'address:" + b + "', window = 'address:" + a + "' }))";
}

// Leave the overview's submap (its name carries a version, see lua/overview-mode.lua),
// whatever submap is active; a no-op otherwise.
var LEAVE_OVERVIEW_MODE = "if hl.get_current_submap():find('^snap_layouts_overview') then hl.dispatch(hl.dsp.submap('reset')) end";

// Auto-fit: put windows in the places lib/autosnap.js worked out. `items` are its
// plan items; only the ones with `move` are touched, and nothing here takes the
// focus. A window still tiled is floated first. Returns "" when there is nothing
// valid to send.
function autoPlace(items) {
    var lua = [];
    (items || []).forEach(function(item) {
        var nums = [item.at && item.at[0], item.at && item.at[1], item.size && item.size[0], item.size && item.size[1]];
        if (!item.move || !validAddress(item.address) || !nums.every(function(n) { return isFinite(n); }))
            return;
        var sel = "'address:" + item.address + "'";
        if (item.float) {
            lua.push("hl.dispatch(hl.dsp.window.float({ action = 'on', window = " + sel + " }))");
            // The tag tells the windows WinSaico floated from those floating on their own,
            // so leaving the mode tiles only the first (release()).
            lua.push("hl.dispatch(hl.dsp.window.tag({ tag = '+" + FLOATED_TAG + "', window = " + sel + " }))");
        }
        lua.push("hl.dispatch(hl.dsp.window.resize({ x = " + Math.round(nums[2]) + ", y = " + Math.round(nums[3]) + ", window = " + sel + " }))");
        lua.push("hl.dispatch(hl.dsp.window.move({ x = " + Math.round(nums[0]) + ", y = " + Math.round(nums[1]) + ", window = " + sel + " }))");
    });
    return lua.join("; ");
}

// A string as one shell word, whatever it holds.
function quote(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'";
}

// What each mode is called in Omarchy's own sentence for it (its catalog key); the
// plugin's mode has a sentence of the plugin's own, passed in.
var OMARCHY_SENTENCE = { dwindle: "layout.workspaceTiling", scrolling: "layout.workspaceScrolling", floating: "layout.workspaceFloating" };

var MODE_LABELS = { dwindle: "tiling", scrolling: "scrolling", floating: "floating", mosaic: "mosaic" };

// Omarchy's state folder, as a quoted shell word; "" unless it is a plain path.
function stateWord(stateDir) {
    return /^\/[A-Za-z0-9._\/-]+$/.test(String(stateDir)) ? "'" + stateDir + "'" : "";
}

// Say something in the notification Omarchy's layout commands share, so one replaces
// the last instead of stacking: its id lives in the state folder. `word` is a shell
// word (quote() a text, or give a command substitution).
function announce(stateDir, word) {
    var notice = "'" + stateDir + "/workspace-layout-notification'";
    return "last=''; [ -r " + notice + " ] && read -r last < " + notice
        + "; n=$(omarchy-notification-send -p -r \"${last:-0}\" -g \u{f10ac} " + word + " 2>/dev/null)"
        + " && case \"$n\" in ''|*[!0-9]*) ;; *) printf '%s\\n' \"$n\" > " + notice + " ;; esac";
}

// Add a workspace number to a file of them (or take it out), one per line.
function listEdit(file, id, add) {
    return "{ grep -vx '" + id + "' " + file + " 2>/dev/null; " + (add ? "echo " + id + "; " : "true; ") + "} > " + file + ".new && mv " + file + ".new " + file;
}

// Set a workspace to one of Omarchy's modes without its announcement: the same call
// and the same saved file as omarchy-hyprland-workspace-layout-toggle makes, so what
// Omarchy restores at the next login is right, but no "set to ..." notification,
// which would be the wrong thing to read when the plugin is entering WinSaico (the
// mode is tiling underneath, and the plugin says its own).
function silentMode(id, mode, stateDir) {
    var call = "o.workspace_mode({ workspace = \"" + id + "\", mode = \"" + mode + "\" })";
    var dir = "'" + stateDir + "/workspace-layouts'";
    var file = "'" + stateDir + "/workspace-layouts/" + id + ".lua'";
    return "if hyprctl eval '" + call + "' >/dev/null 2>&1; then "
        + "if [ \"$(omarchy-hyprland-workspace-layout-default)\" = " + mode + " ]; then rm -f " + file + "; "
        + "else mkdir -p " + dir + "; printf '%s\\n' '" + call + "' > " + file + "; fi; "
        + "omarchy-shell -q omarchy.dock refresh; fi";
}

// The sentence announcing a workspace's mode, as a shell word.
function sentence(target, texts) {
    if (target === "mosaic")
        return quote((texts && texts.mosaic) || "Workspace layout set to WinSaico");
    return "\"$(omarchy-i18n " + OMARCHY_SENTENCE[target] + ")\"";
}

// The windows the plugin floated for WinSaico, when a workspace leaves it: tiled
// again ("tile"), or handed to Omarchy's floating mode, which tiles them when it ends
// ("claim"). The plugin's tag is what tells them from windows that float on their own.
var FLOATED_TAG = "snap-layouts-floated";

function release(workspace, how) {
    var id = Number(workspace);
    if (!(id > 0) || Math.floor(id) !== id || (how !== "tile" && how !== "claim"))
        return "";
    var then = how === "tile"
        ? "hl.dispatch(hl.dsp.window.float({ action = 'off', window = w }))"
        : "hl.dispatch(hl.dsp.window.tag({ tag = '+omarchy-mode-floated', window = w }))";
    return "for _, w in ipairs(hl.get_windows({ tag = '" + FLOATED_TAG + "' })) do "
        + "if tonumber(w.workspace.id) == " + id + " then "
        + "hl.dispatch(hl.dsp.window.tag({ tag = '-" + FLOATED_TAG + "', window = w })); " + then + " end end";
}

// The shell command that puts a workspace in a mode (lib/mode.js `plan` says how):
// record whether the workspace is in the plugin's mosaic list and whether it was set
// to plain tiling (the lists come first so the plugin's hook already knows the
// workspace when windows arrive), give back the windows WinSaico floated when the plan
// says so, then press Omarchy's layout key if it asks for it, and announce the mode
// when the plugin has to. Entering WinSaico sets tiling silently, since Omarchy's own
// message would say tiling.
// `stateDir` is Omarchy's state folder, which already holds its own notification id.
// Returns "" unless the workspace and the folder are plain.
// `place` is optional Lua (the auto-fit's placements): it runs right after the mode has
// changed and before anything slower, so the windows go from where they were straight
// to their places, with no stop in between. `texts.mosaic` is the plugin's sentence
// for its own mode, in the user's language; the other modes use Omarchy's, so the
// message reads exactly as the one Super+L gives.
function layoutCommand(plan, workspace, stateDir, place, texts) {
    var id = Number(workspace);
    var dir = stateWord(stateDir);
    if (!plan || !(id > 0) || Math.floor(id) !== id || dir === "" || !MODE_LABELS[plan.target])
        return "";
    var out = ["mkdir -p " + dir];
    out.push(listEdit("'" + stateDir + "/snap-layouts-workspaces'", id, plan.listed));
    out.push(listEdit("'" + stateDir + "/snap-layouts-plain'", id, plan.plain));
    if (plan.release)
        out.push("hyprctl eval " + quote(release(id, plan.release)) + " >/dev/null 2>&1");
    if (plan.step === "next" || plan.step === "back")
        out.push(plan.target === "mosaic" ? silentMode(id, "dwindle", stateDir) : "omarchy-hyprland-workspace-layout-toggle " + plan.step);
    if (place)
        out.push("hyprctl eval " + quote(place) + " >/dev/null 2>&1");
    if (plan.notify)
        out.push(announce(stateDir, sentence(plan.target, texts)));
    // The bar's layout figure reads the mode again when asked.
    out.push("omarchy-shell -q omarchy.workspaces refresh");
    return out.join("; ");
}

// Put a workspace in the plugin's mosaic list without touching Omarchy's layout: what
// happens to a floating workspace when WinSaico is the default layout.
function listCommand(workspace, stateDir) {
    var id = Number(workspace);
    var dir = stateWord(stateDir);
    if (!(id > 0) || Math.floor(id) !== id || dir === "")
        return "";
    return ["mkdir -p " + dir, listEdit("'" + stateDir + "/snap-layouts-workspaces'", id, true),
        "omarchy-shell -q omarchy.workspaces refresh"].join("; ");
}

// The default layout of workspaces that have none of their own (Appearance >
// Workspace Layout): tiling, scrolling, floating or mosaic. Omarchy's own command
// sets the first three. WinSaico is tiling with a mark of the plugin's (a file in
// the state folder), so the plugin takes new workspaces into the mosaic; the other
// three clear the mark. Returns "" for anything else.
function defaultCommand(target, stateDir, texts) {
    var dir = stateWord(stateDir);
    var native = { tiling: "dwindle", scrolling: "scrolling", floating: "floating", mosaic: "dwindle" }[target];
    if (dir === "" || !native)
        return "";
    var mark = "'" + stateDir + "/snap-layouts-default'";
    // Omarchy's command first, then the mark: the mark has to be newer than the
    // default file, which is how staleMarkCommand tells this from a later choice.
    var out = ["mkdir -p " + dir, "omarchy-hyprland-workspace-layout-default " + native];
    if (target === "mosaic")
        out.push("printf 'mosaic\\n' > " + mark, announce(stateDir, quote((texts && texts.defaultMosaic) || "Default layout set to WinSaico")));
    else
        out.push("rm -f " + mark);
    return out.join("; ");
}

// WinSaico as the default layout is a mark file next to Omarchy's own default
// layout file. If the default is set again by anything else (the menu's other rows,
// `omarchy-hyprland-workspace-layout-default`), Omarchy rewrites its file and the mark
// is older than it: the choice has moved on, so the mark goes. Returns "" unless the
// folder is plain.
function staleMarkCommand(stateDir) {
    if (stateWord(stateDir) === "")
        return "";
    var mark = "'" + stateDir + "/snap-layouts-default'";
    return "[ '" + stateDir + "/workspace-layouts/default.lua' -nt " + mark + " ] && rm -f " + mark + "; true";
}

// What the plugin keeps in Omarchy's state folder: its list of WinSaico workspaces, the
// workspaces set to plain tiling on purpose, and the mark that says WinSaico is the
// default layout. The command that forgets all of it, for uninstalling. Returns "" unless
// the folder is plain.
function forgetCommand(stateDir) {
    if (stateWord(stateDir) === "")
        return "";
    return ["snap-layouts-workspaces", "snap-layouts-plain", "snap-layouts-default"].map(function(name) {
        return "rm -f '" + stateDir + "/" + name + "'";
    }).join("; ");
}
