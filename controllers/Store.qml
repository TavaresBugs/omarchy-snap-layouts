import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/mode.js" as Mode
import "../lib/settings.js" as Settings

// What both of the plugin's entry points (the overlay and the bar button) need to know,
// read once, in one place: the plugin's options in shell.json, and the files that say
// which workspaces are in WinSaico. Both watch the files, so a change made by either
// (or by a command, or by hand) shows in both.
//
// `save` writes options through the shell and applies them at once, before the file has
// been rewritten (`overrides`), so a switch answers the moment it is pressed.
Item {
    id: root

    // The shell's API for plugins; the owner sets it.
    property var shell: null

    readonly property string pluginId: "io.github.n0rthstar88.snap-layouts"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy"

    // shell.json, parsed; the plugin's entry is its plugin record and its bar entry
    // together (lib/settings.js).
    property var config: null
    property bool loaded: false
    property var overrides: ({})
    readonly property var entry: Settings.entryFrom(root.config, root.pluginId)
    readonly property var options: Settings.resolve(Object.assign({}, root.entry || {}, root.overrides))

    // WinSaico's workspaces: the plugin's own list (Omarchy only sees tiling), WinSaico
    // as the default layout (a mark file), and the workspaces set to plain tiling on
    // purpose, which the default does not take over.
    property var mosaicWorkspaces: []
    property bool defaultMosaic: false
    property var plainWorkspaces: []
    readonly property var modeDefaults: ({ defaultMosaic: root.defaultMosaic, plain: root.plainWorkspaces })

    // Save options. False when the shell would not take them.
    function save(changes) {
        if (!root.shell || typeof root.shell.updateEntryInline !== "function") {
            console.warn(root.pluginId + ": can't save " + Object.keys(changes).join(", "));
            return false;
        }
        var base = Object.assign({}, root.entry || {}, root.overrides);
        root.overrides = Object.assign({}, root.overrides, changes);
        root.shell.updateEntryInline(root.pluginId, Settings.changedMany(base, changes));
        return true;
    }

    // The files may not exist until the first change, and a rewrite replaces them, so
    // look again a moment after a change.
    function reloadFiles() {
        mosaicFile.reload();
        defaultFile.reload();
        plainFile.reload();
    }

    function reloadSoon() {
        reloadTimer.restart();
    }

    Timer {
        id: reloadTimer
        interval: 900
        onTriggered: root.reloadFiles()
    }

    function load(raw) {
        try {
            root.config = JSON.parse(raw);
            // A saved change has reached the file: it no longer needs holding.
            var entry = root.entry || {};
            var kept = {};
            Object.keys(root.overrides).forEach(function(key) {
                if (entry[key] !== root.overrides[key])
                    kept[key] = root.overrides[key];
            });
            root.overrides = kept;
        } catch (e) {
            console.warn(root.pluginId + ": could not read shell.json: " + e);
        }
        root.loaded = true;
    }

    FileView {
        // The shell reads this path directly, not via XDG_CONFIG_HOME.
        path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text())
        onLoadFailed: root.loaded = true
        onFileChanged: reload()
    }

    FileView {
        id: mosaicFile
        path: root.stateDir + "/snap-layouts-workspaces"
        watchChanges: true
        printErrors: false
        onLoaded: root.mosaicWorkspaces = Mode.parseList(text())
        onLoadFailed: root.mosaicWorkspaces = []
        onFileChanged: reload()
    }

    FileView {
        id: defaultFile
        path: root.stateDir + "/snap-layouts-default"
        watchChanges: true
        printErrors: false
        onLoaded: root.defaultMosaic = text().trim() === "mosaic"
        onLoadFailed: root.defaultMosaic = false
        onFileChanged: reload()
    }

    FileView {
        id: plainFile
        path: root.stateDir + "/snap-layouts-plain"
        watchChanges: true
        printErrors: false
        onLoaded: root.plainWorkspaces = Mode.parseList(text())
        onLoadFailed: root.plainWorkspaces = []
        onFileChanged: reload()
    }
}
