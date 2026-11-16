# Snap Layouts for Omarchy

[![Omarchy 4 (Quattro) ready](https://img.shields.io/badge/Omarchy_4_(Quattro)-ready-2ea44f)](#compatibility)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)
![Hyprland 0.56](https://img.shields.io/badge/Hyprland-0.56-58e1ff)

Drag a window to the top of the screen, drop it on the layout you want, then choose which windows fill the other spaces. A snap layout picker in the style of Windows 11, built as a shell plugin for [Omarchy](https://omarchy.org). **Omarchy 4 (Quattro) ready.**

This fork adds edge and corner snapping and an Alt+Tab style window overview, and splits the code into tested modules. See [What this fork adds](#what-this-fork-adds).

![Dragging a window onto the layout picker](docs/screenshots/picker-drag.png)

The screenshots show the plugin running in Omarchy's real shell.

## Features

- **Drag to snap:** drag a floating window to the top of a screen and the picker appears. A preview shows where the window will land.
- **Six layouts:** two halves, two-thirds and one-third (either way round), three columns, one half and two quarters, and four quarters.
- **Snap assist:** after the first window lands, pick windows for the remaining spaces from live thumbnails. Only the windows of the workspace being filled are offered (plus the ones minimized from it); windows on other workspaces or screens are not.
- **Keyboard shortcut:** open the picker for the focused window, including tiled windows, which become floating when snapped.
- **Edge and corner snap:** drag a window against the left or right edge for a half, a corner for a quarter, or the top edge for the whole usable area. Hold for a moment and a preview appears; let go to snap, move away to cancel.
- **Window overview (Alt+Tab):** every window of the current workspace as a thumbnail, laid out in tidy rows, with arrow-key and mouse selection. Choosing a window brings it to the front.
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

To open the picker with Super+Z as well, add this line to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + Z", "Snap layouts", hl.dsp.event("io.github.n0rthstar88.snap-layouts:toggle"))
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

| Key | Action |
|---|---|
| Arrow keys | Select the nearest window in that direction |
| Tab / Shift+Tab | Next / previous window |
| Enter or click | Bring the window to the front |
| Ctrl+Left / Ctrl+Right, PageUp / PageDown | Look at the previous / next workspace |
| 1 to 6 | Pick a window by number |
| Esc or click outside | Close |

It shows the windows of the current workspace, plus the ones minimized from it; set `overviewScope` to `"all"` to list every workspace.

**Workspace strip.** At the top, one thumbnail per workspace of the monitor you are on, following Omarchy's per-monitor blocks of ten (the first five always, the others when they hold windows or are current), labelled like the bar. Each thumbnail shows its windows live, at their real positions; empty workspaces are dimmed. Click one, or press Ctrl+Left/Right or PageUp/PageDown, to look at that workspace's windows. Thumbnails are arranged in rows of equal height: one window, two side by side, three as 2+1, four as 2+2, and so on.

**Moving windows.** Drag a thumbnail onto any workspace in the strip to send the window there without leaving the overview. While you drag, the workspace under the pointer previews the result: the window's slot appears in the thumbnail, with the window it will split (50/50, along the longer side) shrinking to make room. A floating window dropped next to tiled ones is tiled on arrival. With more than one monitor there is one strip per screen: the main screen is big and the others small, always in the same order whichever screen you open the overview on. The main screen is an external monitor if there is one (the laptop panel otherwise, then the first workspace block). Click the name of another screen to make it the main one; the choice is saved as `mainMonitor` in `shell.json`, where you can also set it by hand (a connector name such as `"DP-3"`). Changing workspace slides the windows in from the side the new workspace lies on. A window can be dropped onto a workspace of any screen (an empty workspace is created on that screen). Clicking a thumbnail in any strip shows that workspace's windows.

A tiled window can never be drawn above floating ones in Hyprland. When you pick a tiled window that floating windows cover, those floating windows join the tiling layout, so everything stays visible and resizable. Pinned and fullscreen windows are left alone.

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
| `components/` | QML views driven by properties and signals: layout picker, snap assist, overview, workspace strip, shared window picture |
| `SnapLayouts.qml` | State machine and Hyprland I/O |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Optional Hyprland config that goes with this plugin (a window limiter and key bindings) is in [extras/hyprland](extras/hyprland/README.md).

## Compatibility

Built and tested on **Omarchy 4.0.6 (Quattro)** with Hyprland 0.56.2 and Quickshell 0.3.2. It uses Omarchy's shell plugin system and Hyprland's Lua config, so older Omarchy releases and other desktops won't work.

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

Then delete the Super+Z line from `bindings.lua` if you added it. The plugin's mouse binds go away the next time Hyprland reloads its config.

## Contributing and security

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). The optional title bar script builds BSD-licensed code from hyprland-plugins; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This is an independent project. It isn't affiliated with or endorsed by Microsoft, Omarchy or the Hyprland project. Windows is a trademark of Microsoft Corporation, named here only to describe the style of the feature.
