# Snap Layouts for Omarchy

[![Omarchy 4.5 (Quattro) ready](https://img.shields.io/badge/Omarchy_4.5_(Quattro)-ready-2ea44f)](#compatibility)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)
![Hyprland 0.56](https://img.shields.io/badge/Hyprland-0.56-58e1ff)

Drag a window to the top of the screen, drop it on the layout you want, then choose which windows fill the other spaces. A snap layout picker in the style of Windows 11, built as a shell plugin for [Omarchy](https://omarchy.org). **Omarchy 4.5 (Quattro) ready.**

This fork adds edge and corner snapping, an Alt+Tab style window overview with a workspace strip (look at, move windows between, and reorder workspaces, on every screen), and splits the code into tested modules. See [What this fork adds](#what-this-fork-adds).

![Dragging a window onto the layout picker](docs/screenshots/picker-drag.png)

The screenshots show the plugin running in Omarchy's real shell.

## Features

- **Drag to snap:** drag a floating window to the top of a screen and the picker appears. A preview shows where the window will land.
- **Six layouts:** two halves, two-thirds and one-third (either way round), three columns, one half and two quarters, and four quarters.
- **Snap assist:** after the first window lands, pick windows for the remaining spaces from live thumbnails. Only the windows of the workspace being filled are offered (plus the ones minimized from it); windows on other workspaces or screens are not.
- **Keyboard shortcut:** open the picker for the focused window, including tiled windows, which become floating when snapped.
- **Edge and corner snap:** drag a window against the left or right edge for a half, a corner for a quarter, or the top edge for the whole usable area. Hold for a moment and a preview appears; let go to snap, move away to cancel.
- **Window overview (Alt+Tab):** every window of the current workspace as a thumbnail, laid out in tidy rows, with arrow-key and mouse selection. Choosing a window brings it to the front.
- **Workspace strip:** the workspaces of every screen, with their windows live. Look at one, drag a window onto one, or swap two workspaces' places.
- **Fits your screen:** zones stay clear of the top bar and dock on each monitor.
- **Follows your theme:** colours and fonts come from your Omarchy theme.

## Screenshots

| Snap assist | Finished layout |
|---|---|
| ![Choosing a window for the next space](docs/screenshots/snap-assist.png) | ![Three windows snapped into place](docs/screenshots/snapped-layout.png) |

## Install

Plugins run as unsandboxed code inside your shell, so read the code first if you don't know the source. Then run:

```sh
omarchy plugin add https://github.com/TavaresBugs/omarchy-snap-layouts --enable
```

The first time it loads, a prompt asks whether to keep drag-to-snap on.

To open the picker with Super+Z, and the window overview with Alt+Tab, add these lines to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + Z", "Snap layouts", hl.dsp.event("io.github.n0rthstar88.snap-layouts:toggle"))
o.bind("ALT + TAB", "Window overview", hl.dsp.event("io.github.n0rthstar88.snap-layouts:overview"))
```

## Use

**Drag:** move a floating window with Super+drag, or with a title bar if your windows have one. Take the pointer to the top of the screen, move onto a zone in the picker, and let go. Dropping anywhere else, or dragging well below the picker, cancels it.

**Shortcut:** press Super+Z and click a zone. Press Esc or click outside the picker to cancel.

**Snap assist:** click a window to put it in the highlighted space. Tab skips that space, and Esc finishes early. It doesn't appear if there are no other windows or no spaces left.

Drag-to-snap recognises floating windows best. Tiled windows are detected during a drag too, but that path is less tested; if it misbehaves on your setup, float the window first or use the shortcut.

### Title bars (optional)

Omarchy's windows have no title bars by default. If you want to grab windows by a header, with close, maximize and minimize buttons as in the screenshots, see [Title bars](extras/hyprbars/README.md). The plugin notices when the title bar plugin is loaded and keeps each header inside its zone.

## What this fork adds

Built on [n0rthstar88/omarchy-snap-layouts](https://github.com/n0rthstar88/omarchy-snap-layouts) (MIT).

### Edge and corner snap

Drag a window against a screen edge and hold for about 0.3 s:

| Where | Result |
|---|---|
| Left or right edge | Half of the screen |
| A corner | A quarter |
| Top edge | The whole usable area (below the bar) |

A tinted preview shows where the window will land. Release to snap; move away to cancel. This is a quick fit: it doesn't open snap assist.

### Window overview

Bind a key to open it, for example Alt+Tab:

```lua
o.bind("ALT + TAB", "Window overview", hl.dsp.event("io.github.n0rthstar88.snap-layouts:overview"))
```

It shows the windows of the current workspace (plus the ones minimized from it) as thumbnails in rows of equal height: one window, two side by side, three as 2+1, four as 2+2, and so on. Set `overviewScope` to `"all"` to list every workspace instead.

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

To keep another shortcut live, or if you changed one of those, list it in a global `snap_layouts_overview_keep` in your Hyprland config; the format is at the top of [`overview-mode.lua`](overview-mode.lua), which defines the Hyprland submap that does this. The plugin leaves the submap when the overview closes, and resets it if it starts up while it is active.

## Commands

```sh
omarchy-shell snaplayouts toggle            # open or close the picker
omarchy-shell snaplayouts close             # close it
omarchy-shell snaplayouts choose 0 1        # with the picker open: layout 0, zone 1 (right half)
omarchy-shell snaplayouts drag on           # also: off, status
omarchy-shell snaplayouts overview          # open or close the window overview
omarchy-shell snaplayouts focus 0x55d0c8b4  # bring a window forward by address, as choosing it does
```

Layouts and zones count from 0, left to right as shown in the picker. The drag-to-snap choice is saved in `~/.config/omarchy/shell.json`.

## Options

Options go in this plugin's entry in `~/.config/omarchy/shell.json`. Anything missing or invalid falls back to the default, and the file is watched, so changes apply without a restart.

```json
{ "id": "io.github.n0rthstar88.snap-layouts",
  "dragToSnap": true,
  "edgeSnap": true,
  "edgeDwellMs": 320,
  "edgeMargin": 12,
  "edgeCorner": 90,
  "overviewScope": "workspace",
  "mainMonitor": "" }
```

| Option | Default | Meaning |
|---|---|---|
| `edgeSnap` | `true` | Snap by dragging against an edge or corner |
| `edgeDwellMs` | `320` | How long to hold there before the preview shows (0 to 3000) |
| `edgeMargin` | `12` | Pixels from the edge that count as "at the edge" (1 to 80) |
| `edgeCorner` | `90` | Pixels along an edge that count as a corner (10 to 400) |
| `overviewScope` | `"workspace"` | `"workspace"` or `"all"` |
| `mainMonitor` | `""` | Connector shown big in the overview strip, e.g. `"DP-3"`; empty = an external monitor if any. Also set by clicking a screen's name |

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
| `lib/` | Pure logic as QML JavaScript libraries: zone geometry, edge targets, monitors, workspace strip, window ordering, overview layout and navigation, options. No Qt objects, tested with node |
| `components/` | QML views driven by properties and signals: layout picker, snap assist, overview, workspace strip, shared thumbnail frame and window picture |
| `SnapLayouts.qml` | State machine and Hyprland I/O |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Optional Hyprland config that goes with this plugin (a window limiter and key bindings) is in [extras/hyprland](extras/hyprland/README.md).

## Compatibility

Built and tested on **Omarchy 4.5.0 (Quattro)** with Hyprland 0.56.2 and Quickshell 0.3.2. It uses Omarchy's shell plugin system and Hyprland's Lua config, so older Omarchy releases and other desktops won't work.

Testing covered dragging by title bar and by a Hyprland mouse bind, snap assist, the picker commands, turning drag-to-snap off, and snapping a tiled window. Those checks ran on a single screen. Zones are worked out per monitor, but multi-monitor, scaled and rotated setups weren't part of them.

## Troubleshooting

- **The picker doesn't appear when dragging:** check `omarchy-shell snaplayouts drag status` says `on`, that the window is floating, and that the pointer reaches the top 30 pixels of the screen.
- **Dragging a title bar does nothing, but Super+drag works:** the title bar plugin wasn't built with [the drag events](extras/hyprbars/README.md). `extras/hyprbars/rebuild-hyprbars.sh` adds them and warns if it can't.
- **Windows overlap or leave gaps:** set `borderSize` to match your Hyprland border.
- **`Target not found` from `omarchy-shell`:** the plugin isn't running. Check `omarchy plugin list`, then try `omarchy restart shell`.

## Uninstall

```sh
omarchy plugin remove io.github.n0rthstar88.snap-layouts
```

Then undo whatever you added by hand:

- **Key bindings:** delete the Super+Z and Alt+Tab lines from `~/.config/hypr/bindings.lua`.
- **Window limits** (if you installed [the extra](extras/hyprland/README.md#window-limits)): remove `require("hypr.window-limits")` from `~/.config/hypr/hyprland.lua` and delete `~/.config/hypr/window-limits.lua`.
- **Title bars** (if you installed them): follow [Remove](extras/hyprbars/README.md#remove).
- **Options:** if an entry with this plugin's id is still in `~/.config/omarchy/shell.json`, delete it. It holds your options, including the main screen chosen in the overview.

Run `hyprctl reload` afterwards. The plugin's mouse binds go away the next time Hyprland reloads its config.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). The optional title bar script builds BSD-licensed code from hyprland-plugins; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This is an independent project. It isn't affiliated with or endorsed by Microsoft, Omarchy or the Hyprland project. Windows is a trademark of Microsoft Corporation, named here only to describe the style of the feature.
