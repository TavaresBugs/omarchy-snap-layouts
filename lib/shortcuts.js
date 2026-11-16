.pragma library

// The plugin's own keyboard shortcuts, so nobody has to edit bindings.lua. A
// shortcut is written the way Omarchy writes them ("SUPER + Z", "ALT + TAB").
// The plugin binds it at runtime and tags the bind with a description that
// carries the key, which is how it later tells its own binds from anyone else's.
//
// A shortcut set on purpose belongs to the plugin. Whatever else is bound to the
// same keys (Omarchy's Alt+Tab cycling, say, or a bind written by hand for the
// same job) is replaced for as long as the plugin runs, the way Omarchy's own
// `o.rebind` does; a config reload brings those binds back and the plugin
// takes the keys again.
//
// Hyprland 0.56.2 crashes on removing a bind by its handle, so the plugin never
// does: changing or dropping a shortcut means reloading the config (which
// clears runtime binds) and binding what is wanted again. `plan` decides what a
// situation needs. Pure functions.

var PLUGIN = "io.github.n0rthstar88.snap-layouts:";

// Option name -> the event the plugin listens for.
var SHORTCUTS = { picker: "toggle", overview: "overview" };

var MODS = {
    SHIFT: 1, CAPS: 2, CTRL: 4, CONTROL: 4, ALT: 8, MOD1: 8, MOD2: 16, MOD3: 32,
    SUPER: 64, WIN: 64, LOGO: 64, MOD4: 64, META: 64, MOD5: 128
};

// "SUPER + SHIFT + Z" -> { modmask: 65, key: "Z" }; null if it is not a shortcut
// Hyprland would accept (an unknown modifier, no key, odd characters).
function parse(spec) {
    if (typeof spec !== "string")
        return null;
    var parts = spec.split("+").map(function(p) { return p.trim(); });
    var key = parts.pop();
    if (!/^[A-Za-z0-9_:]+$/.test(key))
        return null;
    var modmask = 0;
    for (var i = 0; i < parts.length; i++) {
        var bit = MODS[parts[i].toUpperCase()];
        if (!bit)
            return null;
        modmask |= bit;
    }
    return { modmask: modmask, key: key };
}

function valid(spec) {
    return parse(spec) !== null;
}

// The description a plugin bind carries: its event and the key it was bound to.
function tag(name, spec) {
    return PLUGIN + "shortcut:" + name + ":" + spec;
}

function description(bind) {
    return String((bind && bind.description) || "");
}

// What to do about the wanted shortcuts, given `hyprctl -j binds`.
//   wanted: { picker: "SUPER + Z", overview: "" }   ("" = none)
// Returns { add: { picker: "SUPER + Z" }, replace: { picker: ["Zoom"] }, reload: bool, skipped }
// - already bound as wanted: nothing to do;
// - bound by the plugin to another key, or no longer wanted: a reload is needed
//   (nothing is added meanwhile; the plugin plans again after the reload);
// - otherwise add it; `replace` lists the descriptions of the other binds on the
//   same keys it will take over (absent when the keys are free);
// - not a shortcut Hyprland understands: skipped, with the reason.
function plan(binds, wanted) {
    var out = { add: {}, replace: {}, reload: false, skipped: [] };
    Object.keys(SHORTCUTS).forEach(function(name) {
        var spec = wanted[name] || "";
        var prefix = PLUGIN + "shortcut:" + name + ":";
        var mine = binds.filter(function(b) { return description(b).indexOf(prefix) === 0; });
        var parsed = spec === "" ? null : parse(spec);
        if (spec !== "" && !parsed) {
            out.skipped.push({ name: name, spec: spec, reason: "not a valid shortcut" });
            return;
        }
        if (mine.some(function(b) { return description(b) !== tag(name, spec); })) {
            out.reload = true;
            return;
        }
        if (!parsed || mine.length > 0)
            return;
        var holders = binds.filter(function(b) {
            return Number(b.modmask) === parsed.modmask
                && String(b.key).toLowerCase() === parsed.key.toLowerCase()
                && description(b).indexOf(PLUGIN) !== 0;
        });
        out.add[name] = spec;
        if (holders.length > 0)
            out.replace[name] = holders.map(function(b) { return description(b) || "(no description)"; });
    });
    return out;
}

// The Lua that defines `snap_layouts_shortcuts` (and which of them replace other
// binds) for shortcuts.lua; only valid shortcuts are included, every string quoted.
function assignLua(add, replace) {
    var names = Object.keys(add).filter(function(n) { return SHORTCUTS[n] && valid(add[n]); });
    var shortcuts = names.map(function(n) { return n + " = " + JSON.stringify(add[n]); });
    var replacing = names.filter(function(n) { return replace && replace[n]; }).map(function(n) { return n + " = true"; });
    return "snap_layouts_shortcuts = { " + shortcuts.join(", ") + " }; snap_layouts_shortcuts_replace = { " + replacing.join(", ") + " }";
}
