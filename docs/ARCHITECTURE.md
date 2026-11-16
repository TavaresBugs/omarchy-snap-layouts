# Architecture

## Layers

```
SnapLayouts.qml      state machine, Hyprland I/O, settings, IPC
   │  properties / signals              │  plain function calls
components/          views              lib/        decisions (pure JS)
```

**`lib/`** holds every decision (and the Lua it sends to Hyprland) that can be made from plain data: where a zone lands, which zone the pointer is asking for, how windows are ordered, how thumbnails are laid out, which arrow key goes where, what the options mean. The files are QML JavaScript libraries (`.pragma library`) and use no Qt objects, so `test/load.js` can load them in node and `npm test` covers them.

**`components/`** only draw. Each takes data as properties and reports what the user did as signals. They never read Hyprland or the plugin's state, so they can be reused or restyled on their own. `WindowPicture` (rounded capture with an icon fallback) is shared by the overview and snap assist.

**`SnapLayouts.qml`** owns what is left: the current mode, polling `hyprctl` while a button is held, the Hyprland and shell events, the IPC handler, reading `shell.json`, and issuing `hyprctl eval` commands. It converts between Hyprland's data and the libraries' inputs, and feeds results to the components.

## Modes

`mode` is one of:

| Mode | Meaning |
|---|---|
| `""` | Hidden |
| `picker` | Layout picker opened by the shortcut |
| `drag` | Picker shown because a window is held near the top |
| `edge` | Preview of an edge/corner zone while dragging |
| `assist` | Choosing windows for the remaining zones |
| `overview` | Window overview (Alt+Tab) |

## Data flow for a drag

1. The mouse binds in `hook.lua` report press and release as Hyprland events.
2. On press, a snapshot of monitors and windows is taken; while the button is held the cursor and windows are polled every 60 ms.
3. A window whose position changed is the one being dragged.
4. `Edge.edgeTarget` and the picker hit test turn the cursor position into a layout and zone, which the components preview.
5. On release the window is placed with `hyprctl eval` (float, resize, move).

## Overview

`startOverview` takes a snapshot, filters and orders the windows (`Windows`), lays them out (`Overview.layoutRows`) and sets `overviewT` from 0 to 1, which `OverviewCard` uses to slide each thumbnail from the real window's rect to its place. Choosing a window goes through `focusWindow`: floating windows covering a tiled target are tiled, a minimized window is restored, then the window is focused and raised.

## Workspaces

Omarchy gives each monitor a block of ten workspaces (monitor 1: 1-10, monitor 2: 11-20) and the bar labels them by position. `lib/workspaces.js` applies the same rule: `buildStrip` returns the first five of the current monitor's block (plus later ones that hold windows), each with its windows as fractions of their monitor, and `stepWorkspace` moves between them. `refreshOverview` re-lays-out the windows of whichever workspace the strip has selected. `otherStrips` builds a smaller strip for each other monitor.

## Moving a window between workspaces

`OverviewCard` reports a drag (past a small threshold) as scene coordinates; `OverviewLayer` shows a ghost of the window, asks each `WorkspaceStrip` which workspace is under the pointer (`idAt`) and, on release, emits `moveRequested`. `SnapLayouts` builds the Lua with `lib/dispatch.js` and sends it through `hyprctl eval`, then re-reads the state and re-lays-out. A workspace that does not exist yet would be created on the window's own monitor, so for an empty slot of another screen `moveToWorkspace` shows the workspace on its owner for a moment and then restores that monitor's view and the focused window.

## Layers and notifications

Notifications live on the Overlay layer. The overview uses the Top layer so notifications stay above it, except when the active window is fullscreen, which hides the Top layer; there it falls back to Overlay.

## Adding a feature

Put the decision in `lib/` with a test first; add or extend a component for the view; wire both in `SnapLayouts.qml`. If it needs a user option, add it to `lib/settings.js` with a default and a test, then document it in the README.
