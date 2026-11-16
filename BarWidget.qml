import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons // qmllint disable import
import qs.Ui // qmllint disable import
import "components"
import "controllers"
import "lib/mode.js" as Mode

// The plugin's button in the bar. Click it and a card opens (Panel.qml) with the three
// products' controls: WinSaico for the workspace on screen, with auto-fit, then Alt+Tab
// and Snapping. The button is dimmed while all three are off.
//
// The switches change the plugin's options in shell.json, the same ones the commands
// set; the store (controllers/Store.qml) reads them back and the plugin watches the
// file, so a change applies at once. The workspace's mode and auto-fit go through the
// plugin's own commands, so the card, Super+L and a command do the same thing.
BarWidget {
    id: root

    readonly property string pluginId: "io.github.n0rthstar88.snap-layouts"
    moduleName: root.pluginId

    // The options and the lists of WinSaico workspaces (shared with the overlay).
    Store {
        id: store
        shell: root.bar ? root.bar.shell : null
    }
    readonly property var options: store.options
    readonly property bool anyOn: root.options.winsaico || root.options.overview || root.options.snap

    // The workspace on screen: what Omarchy says its layout is, and so the mode Super+L
    // would show for it (lib/mode.js).
    property string omarchyMode: ""
    readonly property int workspace: Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : 0
    readonly property string mode: Mode.current(root.omarchyMode, store.mosaicWorkspaces, root.workspace,
        { defaultMosaic: store.defaultMosaic, plain: store.plainWorkspaces })

    readonly property Item button: buttonItem
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    implicitWidth: buttonItem.implicitWidth
    implicitHeight: buttonItem.implicitHeight

    // Switch a product on or off: "winsaico", "overview" or "snap".
    function setProduct(name, on) {
        var change = {};
        change[name] = on;
        return store.save(change);
    }

    // Put the workspace on screen in a mode: tiling, scrolling, floating or mosaic.
    // The plugin does the work, so Super+L and this card do the same thing.
    function setMode(name) {
        Quickshell.execDetached(["omarchy-shell", "snaplayouts", "layout", name]);
        modeRefresh.restart();
    }

    // Auto-fit on or off. The plugin does the work, so the card, the command and a
    // shortcut do the same thing (and turning it on fits the windows at once).
    function setAutoFit(on) {
        Quickshell.execDetached(["omarchy-shell", "snaplayouts", "autofit", on ? "on" : "off"]);
    }

    function refreshMode() {
        if (!modeProc.running)
            modeProc.running = true;
        store.reloadFiles();
    }

    function injectPanel() {
        var target = panelLoader.item;
        if (!target)
            return;
        if ("hostWidget" in target)
            target.hostWidget = root;
        if ("anchorItem" in target)
            target.anchorItem = buttonItem;
        if ("bar" in target)
            target.bar = root.bar;
    }

    function open() { if (panelLoader.item) panelLoader.item.open(); }
    function close() { if (panelLoader.item) panelLoader.item.close(); }
    function togglePanel() { if (panelLoader.item) panelLoader.item.toggle(); }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch(); }

    onBarChanged: injectPanel()
    onWorkspaceChanged: root.refreshMode()
    onOpenedChanged: {
        if (root.opened)
            root.refreshMode();
    }
    Component.onCompleted: root.refreshMode()

    Process {
        id: modeProc
        command: ["omarchy-hyprland-workspace-layout-current"]
        stdout: StdioCollector {
            onStreamFinished: root.omarchyMode = text.trim()
        }
    }

    // A mode change takes a moment to apply; look again once it has.
    Timer {
        id: modeRefresh
        interval: 1200
        onTriggered: root.refreshMode()
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: {
            root.injectPanel();
            Qt.callLater(root.injectPanel);
        }
    }

    BarIconButton {
        id: buttonItem
        anchors.fill: parent
        bar: root.bar
        // The WinSaico figure: four squares, the outer corners rounded.
        iconComponent: Component {
            MosaicIcon {
                color: buttonItem.foreground
                size: Style.bar.iconSize
            }
        }
        tooltipText: ""
        active: root.anyOn || root.opened
        useActiveColor: false
        dimmed: !root.anyOn
        onPressed: function() { root.togglePanel(); }
    }

    IpcHandler {
        target: "snaplayouts.bar"

        function toggle(): void { root.togglePanel() }
        function open(): void { root.open() }
        function close(): void { root.close() }
    }
}
