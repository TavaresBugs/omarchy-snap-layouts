.pragma library

// WinSaico in Omarchy's menu: Appearance > Workspace Layout, the layout workspaces get
// when they have none of their own. The rows live in the user's menu extension
// (~/.config/omarchy/extensions/omarchy-menu.jsonc) in a block of their own, between two
// marker comments, so the plugin can add them when WinSaico is on and take them out
// again without touching anything else in the file. Pure functions over the file's text.
//
// WinSaico is Omarchy's tiling plus a mark of the plugin's, so Omarchy's own Tiling row
// would tick too (it only sees tiling). The block restates that row with a tick that
// needs the mark to be absent. A row in the extension replaces the default one whole
// (label, icon and action included), so the label is passed in, already in the user's
// language.

var BEGIN = "// >>> snap-layouts (managed by the Snap Layouts plugin; removed with WinSaico)";
var END = "// <<< snap-layouts";

var DIR = '"${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/snap-layouts-default"';
var DEFAULT = "$(omarchy-hyprland-workspace-layout-default)";

// The rows, as the lines of the block. `tiling` is Omarchy's label for its Tiling row,
// in the language it is set to.
function rows(tiling, winsaico) {
    var tilingRow = {
        icon: "󱓻",
        label: tiling,
        checked: "[[ " + DEFAULT + ' == "dwindle" && ! -e ' + DIR + " ]]",
        action: "omarchy-hyprland-workspace-layout-default dwindle"
    };
    var winsaicoRow = {
        icon: "󰕰",
        label: winsaico,
        checked: "[[ " + DEFAULT + ' == "dwindle" && -e ' + DIR + " ]]",
        action: "omarchy-shell snaplayouts defaultLayout winsaico"
    };
    return [
        '  "appearance.workspace-layout.dwindle": ' + JSON.stringify(tilingRow) + ",",
        '  "appearance.workspace-layout.mosaic": ' + JSON.stringify(winsaicoRow)
    ];
}

// Omarchy's reading of a menu file: whole-line comments and trailing commas go.
function strip(raw) {
    return String(raw || "")
        .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
        .replace(/,(\s*[}\]])/g, "$1");
}

// Is this text a menu Omarchy would read? Empty and comment-only files count.
function valid(raw) {
    var text = strip(raw);
    if (text.trim() === "")
        return true;
    try {
        var parsed = JSON.parse(text);
        return parsed !== null && typeof parsed === "object" && !Array.isArray(parsed);
    } catch (e) {
        return false;
    }
}

function hasBlock(raw) {
    return String(raw || "").indexOf(BEGIN) !== -1;
}

// The rows a hand-made install of the plugin's extras left, with no markers.
function isLegacyRow(line) {
    return /^\s*"appearance\.workspace-layout\.(dwindle|mosaic)"/.test(line) && line.indexOf("snap-layouts-default") !== -1;
}

function isLegacyNote(line) {
    return /^\s*\/\/\s*WinSaico \(Snap Layouts plugin\)/.test(line);
}

// The index just past the last character of a line that is code, not a trailing
// comment: a "//" inside a string (an action with a URL) is not a comment.
function codeEnd(line) {
    var inString = false;
    var end = 0;
    for (var i = 0; i < line.length; i++) {
        var c = line.charAt(i);
        if (inString) {
            if (c === "\\")
                i++;
            else if (c === '"')
                inString = false;
            end = i + 1;
        } else if (c === '"') {
            inString = true;
            end = i + 1;
        } else if (c === "/" && line.charAt(i + 1) === "/") {
            break;
        } else if (!/\s/.test(c)) {
            end = i + 1;
        }
    }
    return end;
}

// The text without the plugin's block (and without legacy hand-made rows), with the
// object left tidy: no comma dangling before the closing brace.
function remove(raw) {
    var lines = String(raw || "").split("\n");
    var out = [];
    var inside = false;
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line.trim() === BEGIN) {
            inside = true;
            continue;
        }
        if (inside) {
            if (line.trim() === END)
                inside = false;
            continue;
        }
        if (isLegacyRow(line) || isLegacyNote(line))
            continue;
        out.push(line);
    }
    return dropTrailingComma(out.join("\n"));
}

// Remove a comma that is the last thing before the closing brace.
function dropTrailingComma(text) {
    var close = text.lastIndexOf("}");
    if (close === -1)
        return text;
    var lines = text.slice(0, close).split("\n");
    for (var i = lines.length - 1; i >= 0; i--) {
        var trimmed = lines[i].trim();
        if (trimmed === "" || trimmed.indexOf("//") === 0)
            continue;
        var end = codeEnd(lines[i]);
        if (lines[i].charAt(end - 1) === ",")
            lines[i] = lines[i].slice(0, end - 1) + lines[i].slice(end);
        break;
    }
    return lines.join("\n") + text.slice(close);
}

// The text with the plugin's block as the last thing in the object. Null when the file
// is not something it can add to (not a menu, or the result would not be one), so it is
// left as it is.
function install(raw, block) {
    var text = remove(raw);
    if (!valid(text))
        return null;
    var lines = block;
    var body = [BEGIN].concat(lines, [END]).join("\n");
    if (strip(text).trim() === "") {
        var comments = text.trim() === "" ? "" : text.trim() + "\n";
        return comments + "{\n" + body + "\n}\n";
    }
    var close = text.lastIndexOf("}");
    if (close === -1 || text.slice(close + 1).replace(/^\s*(\/\/[^\n]*\n?)*\s*$/, "") !== "")
        return null;
    var before = text.slice(0, close).split("\n");
    for (var i = before.length - 1; i >= 0; i--) {
        var trimmed = before[i].trim();
        if (trimmed === "" || trimmed.indexOf("//") === 0)
            continue;
        var end = codeEnd(before[i]);
        var last = before[i].charAt(end - 1);
        if (last !== "{" && last !== ",")
            before[i] = before[i].slice(0, end) + "," + before[i].slice(end);
        break;
    }
    var head = before.join("\n").replace(/\s+$/, "");
    var result = head + "\n" + body + "\n" + text.slice(close);
    return valid(result) ? result : null;
}

// What keeping the block in step with a switch means for this text: the text to write,
// or null when the file already is as it should be (or cannot be edited, and is left
// alone). `block` is rows(...) when WinSaico is on, and null when it is off.
function sync(raw, block) {
    var text = String(raw || "");
    if (block === null || block === undefined) {
        var removed = remove(text);
        return removed === text ? null : removed;
    }
    if (text.indexOf([BEGIN].concat(block, [END]).join("\n")) !== -1 && remove(text) !== text && !hasLegacy(text))
        return null;
    var installed = install(text, block);
    return installed === text ? null : installed;
}

function hasLegacy(raw) {
    return String(raw || "").split("\n").some(function(line) { return isLegacyRow(line) || isLegacyNote(line); });
}
