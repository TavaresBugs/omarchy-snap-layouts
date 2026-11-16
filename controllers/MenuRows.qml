import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/menu.js" as Menu

// WinSaico in Omarchy's menu (Appearance > Workspace Layout), kept in step with its
// switch: the rows are added to the user's menu extension while WinSaico is on and taken
// out when it is off, in a block of their own (lib/menu.js), so nothing else in the file
// is touched. A file the plugin cannot edit safely is left alone and the shell log says so.
//
// Omarchy's Tiling row has to be restated (it would tick along with WinSaico), and a row
// in the extension replaces the default one whole, so its label is read from Omarchy's own
// catalog, in the language Omarchy is set to.
Item {
    id: root

    // WinSaico's switch.
    property bool wanted: false
    // Set by the host once the options are known, so a file is never written on a guess.
    property bool ready: false

    readonly property string configDir: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
    readonly property string menuPath: root.configDir + "/omarchy/extensions/omarchy-menu.jsonc"

    // Omarchy's label for its Tiling row, in the user's language; empty until read.
    property string tilingLabel: ""
    property bool labelDone: false
    property bool fileDone: false
    property string fileText: ""
    property bool warned: false

    function labelCommand() {
        return 'lang=$(cat ' + JSON.stringify(root.configDir + "/omarchy/language") + ' 2>/dev/null); '
            + 'for l in "${lang:-en}" en; do '
            + 'v=$(jq -r \'.["appearance.workspace-layout.dwindle"].label // empty\' ' + JSON.stringify(root.omarchyPath + "/default/i18n/") + '"$l"/menu.json 2>/dev/null); '
            + '[ -n "$v" ] && { printf %s "$v"; exit 0; }; done; printf Tiling';
    }

    function readLabel() {
        if (!labelProc.running)
            labelProc.running = true;
    }

    // Write the rows (or take them out) if the file is not as it should be.
    function sync() {
        if (!root.ready || !root.labelDone || !root.fileDone)
            return;
        var block = root.wanted ? Menu.rows(root.tilingLabel, "WinSaico") : null;
        var current = root.fileText;
        var next = Menu.sync(current, block);
        if (next === null) {
            if (block !== null && !Menu.valid(current) && !root.warned) {
                root.warned = true;
                console.warn("snap-layouts: " + root.menuPath + " is not a menu Omarchy can read, so WinSaico's rows were not added to it");
            }
            return;
        }
        root.fileText = next;
        menuFile.setText(next);
    }

    onWantedChanged: root.sync()
    onReadyChanged: root.sync()

    Process {
        id: labelProc
        command: ["bash", "-c", root.labelCommand()]
        stdout: StdioCollector {
            onStreamFinished: {
                var label = text.trim();
                if (label !== root.tilingLabel)
                    root.tilingLabel = label !== "" ? label : "Tiling";
                root.labelDone = true;
                root.sync();
            }
        }
    }

    // A new language is a new label.
    FileView {
        path: root.configDir + "/omarchy/language"
        watchChanges: true
        printErrors: false
        onFileChanged: root.readLabel()
    }

    Process {
        id: makeDir
        command: ["mkdir", "-p", root.configDir + "/omarchy/extensions"]
        onExited: root.sync()
    }

    FileView {
        id: menuFile
        path: root.menuPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.fileText = text();
            root.fileDone = true;
            root.sync();
        }
        // No extension yet: it starts as an empty one if the rows are wanted.
        onLoadFailed: {
            root.fileText = "";
            root.fileDone = true;
            if (root.wanted && root.ready)
                makeDir.running = true;
        }
        onFileChanged: reload()
    }

    Component.onCompleted: root.readLabel()
}
