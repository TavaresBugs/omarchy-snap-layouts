import QtQuick
import qs.Commons // qmllint disable import
import qs.Ui // qmllint disable import
import "components"

// The card the bar button opens. The plugin is three products, so it has three
// controls: WinSaico at the top (on for the workspace on screen, with auto-fit as its
// complement beneath), then Alt+Tab (the window overview) and Snapping. Everything else
// (the keys, the overview's scope, the snap's sensitivity) is an option in shell.json or
// a command. It only shows the options and asks the bar button (BarWidget.qml) to
// save a change.
Panel {
    id: root
    moduleName: "io.github.n0rthstar88.snap-layouts"
    ipcTarget: "snaplayouts.panel"
    manageIpc: false

    property var hostWidget: null
    property var anchorItem: null
    readonly property var barIdentity: hostWidget || root
    readonly property Item focusTarget: keyCatcher

    readonly property var options: hostWidget ? hostWidget.options : ({})
    // WinSaico on the workspace on screen.
    readonly property bool winsaico: hostWidget ? hostWidget.mode === "mosaic" : false
    readonly property color contentForeground: bar ? bar.foreground : Color.foreground
    readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

    Translations {
        id: strings
        directory: Qt.resolvedUrl("i18n")
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        centerOnBar: false
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(340))
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()

            Column {
                id: column
                width: parent.width
                spacing: Style.space(10)

                PanelHero {
                    id: hero
                    title: "WinSaico"
                    meta: root.winsaico ? strings.t("panel.winsaico.on") : strings.t("panel.winsaico.off")
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    iconComponent: Component {
                        MosaicIcon {
                            color: root.contentForeground
                            size: Style.font.display
                        }
                    }
                    trailingControl: Component {
                        ToggleSwitch {
                            checked: root.winsaico
                            foreground: root.contentForeground
                            onToggled: if (root.hostWidget) root.hostWidget.setMode(checked ? "floating" : "mosaic")
                        }
                    }
                }

                // Auto-fit completes WinSaico: windows share the screen in the plugin's
                // mosaic, or stay where they are put.
                Toggle {
                    width: parent.width
                    label: strings.t("panel.autofit")
                    description: checked ? strings.t("panel.autofit.on") : strings.t("panel.autofit.off")
                    checked: root.options.autoFit !== false
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: if (root.hostWidget) root.hostWidget.setAutoFit(!checked)
                }

                PanelSeparator { foreground: root.contentForeground }

                Toggle {
                    width: parent.width
                    label: strings.t("panel.overview")
                    description: strings.t("panel.overview.hint")
                    checked: root.options.overview === true
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: if (root.hostWidget) root.hostWidget.setProduct("overview", !checked)
                }

                Toggle {
                    width: parent.width
                    label: strings.t("panel.snap")
                    description: strings.t("panel.snap.hint")
                    checked: root.options.snap !== false
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    onClicked: if (root.hostWidget) root.hostWidget.setProduct("snap", !checked)
                }
            }
        }
    }
}
