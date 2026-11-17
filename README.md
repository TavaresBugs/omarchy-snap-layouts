# WinSaico and Snap Layouts for Omarchy

[![Omarchy 4.5 (Quattro) ready](https://img.shields.io/badge/Omarchy_4.5_(Quattro)-ready-2ea44f)](#compatibility)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)
![Hyprland 0.56](https://img.shields.io/badge/Hyprland-0.56-58e1ff)

A shell plugin for [Omarchy](https://omarchy.org) with three independent products, each with a switch of its own in the bar:

| Product | What it is | Keys |
|---|---|---|
| **WinSaico** | A fourth workspace layout beside tiling, scrolling and floating: free windows that share the screen. **Auto fit** completes it | Super+L, Super+Alt+L, and Omarchy's Appearance > Workspace Layout menu |
| **Alt+Tab** | A window overview with a live workspace strip | Alt+Tab |
| **Snapping** | A snap layout picker in the style of Windows 11, plus edge and corner snap | Drag a window to the top, an edge or a corner; Super+Z if you give it one |

![Dragging a window onto the layout picker](docs/screenshots/picker-drag.png)

The screenshots show the plugin running in Omarchy's real shell. Built on [n0rthstar88/omarchy-snap-layouts](https://github.com/n0rthstar88/omarchy-snap-layouts) (MIT); the picker is theirs, and this fork adds edge and corner snap, the overview and its workspace strip, WinSaico, and splits the code into tested modules.

## Features

- **WinSaico:** windows free to move, resize and overlap, placed the way the picker places them. With **auto-fit** on they share the screen (one fills it, two share it, three make a half and two quarters, four make quarters, more are dealt in even rows) and a new window takes its place while the others make room; with it off a new window opens in front and in the middle. It is in Super+L's cycle and in Omarchy's layout menu. See [WinSaico](#winsaico-superl).
- **Alt+Tab window overview:** every window of the current workspace as a thumbnail, laid out in tidy rows, with arrow-key and mouse selection, plus a **workspace strip** with the workspaces of every screen, live: look at one, move windows between them, reorder them.
- **Drag to snap:** drag a floating window to the top of a screen and the picker appears, with a preview of where the window will land. Six layouts: two halves, two-thirds and one-third (either way round), three columns, one half and two quarters, and four quarters.
- **Snap assist:** after the first window lands, pick windows for the remaining spaces from live thumbnails. Only the windows of the workspace being filled are offered (plus the ones minimized from it).
- **Edge and corner snap:** drag a window against the left or right edge for a half, a corner for a quarter, or the top edge for the whole usable area.
- **Keyboard shortcut:** open the picker for the focused window, including tiled windows, which become floating when snapped.
- **One card in the bar:** WinSaico for the workspace on screen with auto-fit beneath it, then Alt+Tab and Snapping. No file to edit.
- **Fits your screen:** zones stay clear of the top bar on each monitor.
- **Follows your theme:** colours and fonts come from your Omarchy theme, and the plugin's own sentences are in Omarchy's language (`i18n/`).

## Screenshots

| Snap assist | Finished layout |
|---|---|
| ![Choosing a window for the next space](docs/screenshots/snap-assist.png) | ![Three windows snapped into place](docs/screenshots/snapped-layout.png) |

## Install

Plugins run as unsandboxed code inside your shell, so read the code first if you don't know the source. Then run:

```sh
omarchy plugin add https://github.com/TavaresBugs/omarchy-snap-layouts --enable
```

The three products are on from the start except **Alt+Tab**, which replaces a system key and is yours to turn on (the bar card, or `omarchy-shell snaplayouts product overview on`).

### What the plugin changes on your system

Nothing in your own files except one block in your menu extension, and each change goes away with its switch:

| What | Where | Goes away |
|---|---|---|
| Super+L and Super+Alt+L (WinSaico in the cycle) | Runtime binds that replace Omarchy's layout keys, wherever Omarchy has them | When WinSaico is off or the plugin is removed: Omarchy's keys come back at the next config reload (the plugin reloads once when you switch it off) |
| Alt+Tab | A runtime bind, only while the overview is on | The same |
| **WinSaico** row in Appearance > Workspace Layout | A block between `// >>> snap-layouts` and `// <<< snap-layouts` in `~/.config/omarchy/extensions/omarchy-menu.jsonc`, written and removed by the plugin (it restates Omarchy's Tiling row in your language, because that row would tick along with WinSaico) | When WinSaico is turned off |
| Which workspaces are in WinSaico | Files in `~/.local/state/omarchy/` named `snap-layouts-*` | `omarchy-shell snaplayouts uninstall` |

A menu extension the plugin cannot read as a menu is left alone, and the shell log says so.

### Keyboard shortcuts

WinSaico takes the keys Omarchy has for its layout cycle, wherever you have them (Super+L and Super+Alt+L by default). The overview answers to Alt+Tab. The picker has no key until you give it one, and any of them can be changed:

```sh
omarchy-shell snaplayouts shortcut picker "SUPER + Z"
omarchy-shell snaplayouts shortcut overview "CTRL + TAB"
omarchy-shell snaplayouts shortcut layout "SUPER + K"
```

Write a shortcut the way Omarchy does, in quotes. They are saved as `pickerShortcut`, `overviewShortcut`, `layoutShortcut` and `layoutBackShortcut` in `~/.config/omarchy/shell.json` (you can edit them there too), and bound for you from then on, including after a config reload. To remove one, use `off` in place of the keys (the layout and overview keys then go back to their defaults).

A shortcut set for a product that is on belongs to the plugin: whatever else is bound to the same keys (Omarchy's Alt+Tab window cycling, say, or a bind you wrote for the same job) is replaced while the plugin runs, the way Omarchy's own `rebind` does, and the shell log says what it replaced. A config reload brings the original binds back and the plugin takes the keys again. Changing or removing a shortcut reloads your Hyprland config once, because Hyprland can't safely drop a bind at runtime.

Prefer to bind the picker yourself? Add this to `~/.config/hypr/bindings.lua` instead, and leave the option unset:

```lua
o.bind("SUPER + Z", "Snap layouts", hl.dsp.event("io.github.n0rthstar88.snap-layouts:toggle"))
```

## Use

**Drag:** move a floating window with Super+drag, or with a title bar if your windows have one. Take the pointer to the top of the screen, move onto a zone in the picker, and let go. Dropping anywhere else, or dragging well below the picker, cancels it.

**Shortcut:** press Super+Z and click a zone. Press Esc or click outside the picker to cancel.

**Snap assist:** click a window to put it in the highlighted space. Tab skips that space, and Esc finishes early. It doesn't appear if there are no other windows or no spaces left.

Drag-to-snap recognises floating windows best. Tiled windows are detected during a drag too, but that path is less tested; if it misbehaves on your setup, float the window first or use the shortcut.

### The bar's layout figure

The figure next to the workspace numbers is Omarchy's own widget, which knows three layouts, so a WinSaico workspace shows as tiling there. The plugin's button in the bar shows WinSaico's figure and opens its card.

### Title bars (optional)

Omarchy's windows have no title bars by default. If you want to grab windows by a header, with close, maximize and minimize buttons as in the screenshots, see [Title bars](extras/hyprbars/README.md). The plugin notices when the title bar plugin is loaded and keeps each header inside its zone.

## The products in detail

### Edge and corner snap

Drag a window against a screen edge and hold for about 0.3 s:

| Where | Result |
|---|---|
| Left or right edge | Half of the screen |
| A corner | A quarter |
| Top edge | The whole usable area (below the bar) |

A tinted preview shows where the window will land. Release to snap; move away to cancel. This is a quick fit: it doesn't open snap assist.

### WinSaico (Super+L)

Omarchy's layout key cycles a workspace through tiling, scrolling and floating. With WinSaico on, the plugin adds **WinSaico** to the cycle: tiling, scrolling, floating, WinSaico, tiling again (Super+Alt+L goes the other way), and a notification names the mode, worded as Omarchy's own. The switch at the top of the bar card does the same for the workspace on screen. `omarchy-shell snaplayouts layout winsaico` (or `tiling`, `scrolling`, `floating`) sets one directly. With WinSaico off the keys go back to Omarchy and the cycle is its three modes again.

WinSaico is a workspace in Omarchy's tiling layout whose windows the plugin floats itself, exactly as the picker (Super+Z) floats a window it places. It is deliberately not Omarchy's floating mode, which floats everything that opens there at a set size (a menu or a popup too), draws a title bar on every window and takes over focus. Windows here are free to move, resize and overlap, plus an **auto-fit** switch (the bar button's card, `omarchy-shell snaplayouts autofit toggle`, or a key with `shortcut autoFit "<keys>"`):

| Auto-fit | What happens |
|---|---|
| On | Switching it on (or entering the mode) fits every window of the workspace into the mosaic at once. After that a window that opens takes its place and the others make room, and closing one closes the gap. A window you resized goes back to its place at the next fit. |
| Off | Nothing is touched. A new window opens in front and in the middle, and you size it as you like. |

The mosaic is the plugin's layouts: one window fills the usable area, two make halves, three a half and two quarters, four make quarters, and more are dealt in even rows (five are three over two, eight are two rows of four). The oldest window takes the first zone and a new one goes last. Fullscreen and pinned windows are never moved, and a window that floats on its own account (a dialog, a popup) stays out, unless the mode has just been switched on, which brings everything in once.

Windows in WinSaico have **no title bar** and nothing else of Omarchy's floating mode: a window that would tile when it opens is floated, tagged and given a size in the middle by a small Hyprland hook (`lua/mosaic.lua`), and anything that floats on its own (dialogs, popups, menus) is left exactly as it is. Leaving the mode tiles the windows the plugin floated again (or, going to floating, hands them to Omarchy, which tiles them when floating ends).

**In the layout menu.** Omarchy's menu has Appearance > Workspace Layout, the layout workspaces get when they have none of their own. While WinSaico is on, the plugin keeps a **WinSaico** row there (see [what it changes](#what-the-plugin-changes-on-your-system)). It is Omarchy's tiling default plus a mark of the plugin's, and a workspace that tiles by default joins the mosaic the first time it is shown or gets a window, unless you put it in plain tiling on purpose (Super+L, or the card). Workspaces that already have windows keep the layout they have, as Omarchy always does when the default changes. Choosing any other row in that menu drops the mark. The Tiling row is restated so that it is not ticked at the same time, since Omarchy only sees tiling.

Under the hood the mode is Omarchy's tiling plus the plugin's own list of workspaces (`~/.local/state/omarchy/snap-layouts-workspaces`), so Omarchy never needs to know it exists and the list survives a restart.

**The dock.** Omarchy's own dock appears only on workspaces Omarchy marks as floating. WinSaico is built on tiling on purpose (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)), so the dock does not show there. The plugin does not ship a copy of it: a cloned plugin is handed a narrower shell than Omarchy's own, and loses your dock's settings.

### Window overview

Give it a shortcut (see [Keyboard shortcuts](#keyboard-shortcuts)), for example Alt+Tab. It shows the windows of the current workspace (plus the ones minimized from it) as thumbnails in rows of equal height: one window, two side by side, three as 2+1, four as 2+2, and so on. Set `overviewScope` to `"all"` to list every workspace instead.

Opening runs the real windows into the thumbnails and closing runs them back, so the window you pick lands on itself. A tiled window can never be drawn above floating ones in Hyprland, so when you pick a tiled window that floating windows cover, those floating windows join the tiling layout: everything stays visible and resizable. Pinned and fullscreen windows are left alone.

| Key | Action |
|---|---|
| Arrow keys | Select the nearest window in that direction |
| Up from the top row | Move to the workspace strip |
| Tab / Shift+Tab | Next / previous window |
| Enter or click | Bring the window to the front |
| Ctrl+Left / Ctrl+Right, PageUp / PageDown | Look at the previous / next workspace |
| Super+Shift+arrow | Swap the selected window with its neighbour in the real layout |
| 1 to 9 | Pick a window by its place in the list |
| Esc or click outside | Close |

### Workspace strip

At the top of the overview, one thumbnail per workspace, labelled as in the bar. Each shows its windows live, at their real positions; empty workspaces are dimmed. Omarchy gives every monitor its own block of ten workspaces, and the strip follows that: the first five of each block always, the others when they hold windows or are being looked at.

With more than one monitor there is one strip per screen: the main screen big, the others small, always in the same order whichever screen the overview is opened on. The main screen is an external monitor if there is one (the laptop panel otherwise, then the first workspace block). Click the name of another screen to make it the main one; the choice is saved as `mainMonitor` in `shell.json`, where you can also set it by hand (a connector name such as `"DP-3"`).

- **Look at a workspace:** click its thumbnail, or press Ctrl+Left/Right or PageUp/PageDown. The windows slide in from the side the workspace lies on. The overview also follows the system: Super+1..5 (or any other way of changing workspace) while it is open moves its view there.
- **Go to a workspace:** double-click its thumbnail, or press Enter on it.
- **Move a window:** drag its thumbnail onto any workspace, on any screen (an empty workspace is created on that screen). While you drag, the thumbnail under the pointer previews the result: the window's slot appears in it, with the window it will split (50/50, along the longer side) shrinking to make room. A floating window dropped next to tiled ones is tiled on arrival.
- **Reorder workspaces:** drag a thumbnail onto another one on the same screen, or press Shift+Left/Right (or Super+Shift+Left/Right) on the strip. The two trade numbers and each keeps its windows, so "2 comes to 1 and 1 goes to 2".

On the strip, Left/Right look at the previous/next workspace (across screens, main first), Enter goes to it and Down returns to the windows.

### The overview is modal

While it is open the system's shortcuts are paused, so a key meant for the overview can never act on the windows behind it (Super+Shift+arrow would otherwise swap, even across monitors, a window you can't see). Still live: Alt+Tab (close), Super+1 to Super+0 (switch workspace), Super+Shift+arrow (swap), Escape (close), and what you would want while looking at it: screenshots and screen capture (Print, Super+Ctrl+C and the rest of Omarchy's capture keys), notification keys, and the volume, brightness and media keys, so the overview itself can be captured. Everything else, such as the launcher, works again once it closes.

To keep another shortcut live, or if you changed one of those, list it in a global `snap_layouts_overview_keep` in your Hyprland config; the format is at the top of [`lua/overview-mode.lua`](lua/overview-mode.lua), which defines the Hyprland submap that does this. The plugin leaves the submap when the overview closes, and resets it if it starts up while it is active.

## Commands

```sh
omarchy-shell snaplayouts product winsaico on   # a product's switch: winsaico, overview or snap; on, off, toggle, status
omarchy-shell snaplayouts layout next           # the workspace layout, as Super+L sets it; also: back, tiling, scrolling, floating, winsaico
omarchy-shell snaplayouts defaultLayout winsaico  # the layout workspaces get by default (Appearance > Workspace Layout); also tiling, scrolling, floating
omarchy-shell snaplayouts autofit toggle        # auto-fit in WinSaico; also: on, off, status
omarchy-shell snaplayouts overview              # open or close the window overview
omarchy-shell snaplayouts toggle                # open or close the picker
omarchy-shell snaplayouts close                 # close it
omarchy-shell snaplayouts choose 0 1            # with the picker open: layout 0, zone 1 (right half)
omarchy-shell snaplayouts focus 0x55d0c8b4      # bring a window forward by address, as choosing it does
omarchy-shell snaplayouts shortcut picker "SUPER + Z"  # bind a key (picker, overview, layout, layoutBack, autoFit); "off" removes it
omarchy-shell snaplayouts uninstall             # every product off, the menu rows and state files gone; then omarchy plugin remove
```

Layouts and zones count from 0, left to right as shown in the picker. The switches are saved in `~/.config/omarchy/shell.json`.

## Options

Options go in this plugin's entry in `~/.config/omarchy/shell.json`. Anything missing or invalid falls back to the default, and the file is watched, so changes apply without a restart. The bar card and the commands write the same options.

```json
{ "id": "io.github.n0rthstar88.snap-layouts",
  "winsaico": true,
  "autoFit": true,
  "overview": false,
  "snap": true,
  "edgeDwellMs": 120,
  "edgeMargin": 12,
  "edgeCorner": 60,
  "overviewScope": "workspace",
  "mainMonitor": "",
  "pickerShortcut": "",
  "overviewShortcut": "",
  "layoutShortcut": "",
  "layoutBackShortcut": "",
  "autoFitShortcut": "" }
```

| Option | Default | Meaning |
|---|---|---|
| `winsaico` | `true` | WinSaico: in Super+L's cycle and in the layout menu. Off, Omarchy's keys come back and the menu row goes. Also `product winsaico` |
| `autoFit` | `true` | WinSaico's complement: windows share the screen by themselves; `false` leaves them free and a new window opens in the middle. Also the bar card or `autofit` |
| `overview` | `false` | Alt+Tab, the window overview and workspace strip. On, the plugin binds its key. Also the bar card or `product overview` |
| `snap` | `true` | Snapping: the picker, dragging to the top, an edge or a corner. Also the bar card or `product snap` |
| `edgeDwellMs` | `120` | How long to hold at an edge before the preview shows (0 to 3000) |
| `edgeMargin` | `12` | Pixels from the edge that count as "at the edge" (1 to 80) |
| `edgeCorner` | `60` | Pixels along an edge that count as a corner (10 to 400) |
| `overviewScope` | `"workspace"` | `"workspace"` or `"all"` |
| `mainMonitor` | `""` | Connector shown big in the overview strip, e.g. `"DP-3"`; empty = an external monitor if any. Also set by clicking a screen's name |
| `pickerShortcut` | `""` | A key the plugin binds for the layout picker, e.g. `"SUPER + Z"`; empty = none. Also `shortcut picker` |
| `overviewShortcut` | `""` | The overview's key, also the one that closes it; empty = `"ALT + TAB"`. Also `shortcut overview` |
| `layoutShortcut` | `""` | WinSaico's layout key; empty = the one Omarchy has it on (`"SUPER + L"`). Also `shortcut layout` |
| `layoutBackShortcut` | `""` | The same, going the other way round (`"SUPER + ALT + L"`). Also `shortcut layoutBack` |
| `autoFitShortcut` | `""` | A key that turns auto-fit on and off (`shortcut autoFit "<keys>"`) |

Entries written by earlier versions still work: `enabled: false` turns the three products off, `dragToSnap` and `edgeSnap` (both false) turn Snapping off, and an `overviewShortcut` turns the overview on. The first change saved from the card rewrites the entry in the new form.

## Configuration

These values are at the top of `SnapLayouts.qml`. Hyprland's Lua config doesn't report them to plugins, so change them to match your setup if yours differ, then run `omarchy restart shell`.

| Setting | Default | Meaning |
|---|---|---|
| `outerGap` | `10` | Space between windows and the screen edge |
| `innerGap` | `0` | Space between snapped windows |
| `borderSize` | `2` | Must match Hyprland's `general.border_size` |
| `titleBarHeight` | `24` | Must match hyprbars' `bar_height`, if you use it |
| `dragTriggerDistance` | `30` | How close to the top the pointer must get to open the picker |
| `layouts` | six layouts | Zones as `[x, y, width, height]` fractions of the screen |

Local edits stop `omarchy plugin update` from updating the plugin until you undo them.

## Development

The plugin is split so the decisions can be tested without a running shell:

```sh
npm test        # unit tests for everything in lib/
```

| Folder | Contents |
|---|---|
| `lib/` | Pure logic as QML JavaScript libraries: zone geometry, edge targets, monitors, workspace strip, window ordering, overview layout and navigation, workspace modes, options, shortcuts, menu rows. No Qt objects, tested with node |
| `components/` | QML views driven by properties and signals: layout picker, snap assist, overview, workspace strip, shared thumbnail frame and window picture |
| `controllers/` | Non-visual QML: the options and lists both entry points read (`Store`), WinSaico with auto-fit (`WinSaico`), and WinSaico's rows in Omarchy's menu (`MenuRows`) |
| `lua/` | What runs inside Hyprland: the drag binds, the plugin's shortcuts, WinSaico's window hook, the overview's key submap |
| `SnapLayouts.qml` | The overlay: the picker, snap assist, the overview and the Hyprland I/O around them |
| `BarWidget.qml`, `Panel.qml` | The bar button and its card |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Optional Hyprland config that goes with this plugin (a window limiter and key bindings) is in [extras/hyprland](extras/hyprland/README.md).

## Compatibility

Built and tested on **Omarchy 4.5.0 (Quattro)** with Hyprland 0.56.2 and Quickshell 0.3.2. It uses Omarchy's shell plugin system and Hyprland's Lua config, so older Omarchy releases and other desktops won't work.

Testing covered dragging by title bar and by a Hyprland mouse bind, snap assist, the picker commands, turning drag-to-snap off, and snapping a tiled window. Those checks ran on a single screen. Zones are worked out per monitor, but multi-monitor, scaled and rotated setups weren't part of them.

## Troubleshooting

- **The picker doesn't appear when dragging:** check `omarchy-shell snaplayouts product snap status` says `on`, that the window is floating, and that the pointer reaches the top 30 pixels of the screen.
- **Dragging a title bar does nothing, but Super+drag works:** the title bar plugin wasn't built with [the drag events](extras/hyprbars/README.md). `extras/hyprbars/rebuild-hyprbars.sh` adds them and warns if it can't.
- **Windows overlap or leave gaps:** set `borderSize` to match your Hyprland border.
- **`Target not found` from `omarchy-shell`:** the plugin isn't running. Check `omarchy plugin list`, then try `omarchy restart shell`.

## Uninstall

```sh
omarchy-shell snaplayouts uninstall        # every product off, WinSaico's menu rows and the plugin's state files gone
omarchy plugin remove io.github.n0rthstar88.snap-layouts
```

The first command gives Omarchy its keys back (at the next config reload, which the plugin triggers) and clears what the plugin added. Windows that WinSaico floated stay where they are. Then undo whatever you added by hand:

- **Key bindings:** if you bound the picker yourself, delete those lines from `~/.config/hypr/bindings.lua`.
- **Window limits** (if you installed [the extra](extras/hyprland/README.md#window-limits)): remove `require("hypr.window-limits")` from `~/.config/hypr/hyprland.lua` and delete `~/.config/hypr/window-limits.lua`.
- **Title bars** (if you installed them): follow [Remove](extras/hyprbars/README.md#remove).
- **Options:** if an entry with this plugin's id is still in `~/.config/omarchy/shell.json`, delete it. It holds your options, including the main screen chosen in the overview.

Run `hyprctl reload` afterwards.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). The optional title bar script builds BSD-licensed code from hyprland-plugins; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This is an independent project. It isn't affiliated with or endorsed by Microsoft, Omarchy or the Hyprland project. Windows is a trademark of Microsoft Corporation, named here only to describe the style of the feature.
