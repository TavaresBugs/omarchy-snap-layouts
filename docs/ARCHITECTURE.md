# Architecture

## Layers

```
SnapLayouts.qml      BarWidget.qml + Panel.qml
 overlay: picker,     bar button and its card
 overview, IPC             │
   │                       │      both read the same state
   └──── controllers/ ─────┘      Store (options + lists), WinSaico, MenuRows
   │  properties / signals              │  plain function calls
components/          views              lib/        decisions (pure JS)
                                        lua/        what runs inside Hyprland
```

The plugin is three products with a switch each (`winsaico`, `overview`, `snap`, validated by `lib/settings.js`). WinSaico lives in `controllers/WinSaico.qml`; Snapping and the overview are the overlay's.

**`lib/`** holds every decision (and the Lua it sends to Hyprland) that can be made from plain data: where a zone lands, which zone the pointer is asking for, how windows are ordered, how thumbnails are laid out, which arrow key goes where, what the options mean, how WinSaico's block is written into the menu extension. The files are QML JavaScript libraries (`.pragma library`) and use no Qt objects, so `test/load.js` can load them in node and `npm test` covers them.

**`components/`** only draw. Each takes data as properties and reports what the user did as signals. They never read Hyprland or the plugin's state, so they can be reused or restyled on their own. Two pieces are shared so every thumbnail looks like part of one family: `ThumbFrame` (one soft shadow scaled to the frame, content clipped to rounded corners, a thin ring in the theme's accent drawn above the content so nothing spills over the outline: strong for the selection, soft for the viewed workspace) and `WindowPicture` (a window's capture with an icon fallback). `OverviewCard` (overview and snap assist) and the workspace strip's thumbnails are both built on them.

**`controllers/`** are non-visual QML that own one concern each. `Store` reads `shell.json` and the files that list WinSaico's workspaces, once, for both entry points (the overlay and the bar button are separate QML roots, so they used to read the same files twice), and saves options through the shell with an override that applies a change before the file has been rewritten. `WinSaico` is the mode and auto-fit (below). `MenuRows` keeps WinSaico's rows in Omarchy's menu extension in step with its switch.

**`SnapLayouts.qml`** owns what is left: the current mode of the picker and overview, polling `hyprctl` while a button is held, the Hyprland and shell events, the IPC handler, the binds, and issuing `hyprctl eval` commands. It converts between Hyprland's data and the libraries' inputs, and feeds results to the components.

## The libraries

| File | Decides |
|---|---|
| `layouts.js` | The layouts, where a zone lands on a monitor, the mosaic for any number of windows, the picker's geometry and hit test |
| `edge.js` | Which layout and zone a pointer against an edge or corner asks for |
| `monitors.js` | Hyprland's monitors converted to logical pixels |
| `windows.js` | Which windows are offered and in what order; which floating windows cover a tiled one |
| `autosnap.js` | Auto-fit: which windows take part and which zone of the mosaic each gets |
| `mode.js` | The workspace modes behind Super+L: the ring, which mode a workspace is in, and what it takes to change it |
| `overview.js` | The overview's thumbnail layout and area, and geometric arrow-key navigation |
| `navigation.js` | What a key does in the overview, given where the focus is |
| `workspaces.js` | Omarchy's per-monitor workspace blocks, the strips, the drop preview |
| `motion.js` | Animation tokens, and the motion that follows from the windows' real geometry |
| `dispatch.js` | The Lua sent to Hyprland (moving windows and workspaces, swapping, going to a workspace) |
| `style.js` | The gap to the screen edge and the border width, read from Hyprland |
| `settings.js` | What the options in `shell.json` mean, validated; the products' switches, and how an entry from an earlier version reads |
| `shortcuts.js` | The plugin's own shortcuts: parsing, the layout keys Omarchy has, and what to add, leave alone or reload for, given the binds that exist |
| `menu.js` | WinSaico's block in the user's menu extension: rows, adding, removing, and whether the file needs writing at all |
| `hyprctl.js` | Several `hyprctl` answers gathered in one process and parsed |

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

1. The mouse binds in `lua/hook.lua` report press and release as Hyprland events.
2. On press, a snapshot of monitors and windows is taken; while the button is held the cursor and windows are polled every 60 ms.
3. A window whose position changed is the one being dragged.
4. `Edge.edgeTarget` and the picker hit test turn the cursor position into a layout and zone, which the components preview.
5. On release the window is placed with `hyprctl eval` (float, resize, move).

## Overview

`startOverview` takes a snapshot, filters and orders the windows (`Windows`), lays them out in `Overview.area` (`Overview.layoutRows`) and sets `overviewT` from 0 to 1, which `OverviewCard` uses to slide each thumbnail from the real window's rect to its place. Choosing a window goes through `focusWindow`: floating windows covering a tiled target are tiled, a minimized window is restored, then the window is focused and raised.

## Keys

`lib/navigation.js` turns a key and the current state (focus on the windows or on the strip, selected card, layout) into an action; `SnapLayouts.overviewKey` only translates Qt's event into that input and carries the action out. Up from the top row enters the strip; Shift+arrow on the strip swaps workspace numbers (`Dispatch.swapWorkspaces`, three `change_id` steps through a free number).

## Modal overview

Hyprland handles shortcuts before the focused surface sees a key, so with the overview open a key like Super+Shift+arrow would also act on the windows behind it. `lua/overview-mode.lua` (sent with `hyprctl eval` on every open) defines and enters a submap in which only a few binds exist: Alt+Tab, Super+Shift+arrow (reported to the plugin as `swap-<direction>` events), Super+1..0 (Omarchy's workspace focus), Escape (the submap's reset key), and a `KEEP` list of capture, notification and hardware keys re-bound through Omarchy's own `o.bind` (extendable with a global `snap_layouts_overview_keep`). Unbound keys go on to the overview. `hide()` leaves the submap; a `submap` event with an empty name (Escape) closes the overview; and the plugin resets the submap when it starts, so nothing can leave the shortcuts paused.

## Animation

`lib/motion.js` holds the numbers. Matters of taste (durations, curves, stagger, how big a lift) are `TOKENS`, in one place. Everything that depends on the layout is worked out from where things really are: the selected card is enlarged and lifted only as far as the room it has inside the area windows can use (`emphasis`, so a card on a window that fills the mosaic gets none), and the workspace strip is gone before the first card heading back to its window would cross it (`stripClear`, from the windows' real positions). The cards' own start and end are the windows' real rectangles, read when the overview opens.

`overviewT` (0..1) drives both directions: opening runs it up, `close()` runs it back to 0 and only then hides the overview. Cards sit on their real window at 0 and in their place at 1, each starting a little later than the one before it (the selected card leads), with the icon and title fading in only near the end; the strip comes in last and leaves first, so a card returning to a window that fills the screen never grows under it; when the viewed workspace is not the one on screen they fade instead, unless the overview is closing because a window or workspace was chosen (`closingIntoWorkspace`): that workspace is about to be the visible one, so they travel. The backdrop reaches full opacity in the first third, so the real windows are hidden while the cards still sit on them. A workspace change from outside (`workspacev2` event) re-reads the state and slides the new set in; events caused by the plugin's own moves are ignored for a moment.

## Workspaces

Omarchy gives each monitor a block of ten workspaces (monitor 1: 1-10, monitor 2: 11-20) and the bar labels them by position. `lib/workspaces.js` applies the same rule: `buildStrip` returns the first five of the current monitor's block (plus later ones that hold windows), each with its windows as fractions of their monitor, and `stepWorkspace` moves between them. `refreshOverview` re-lays-out the windows of whichever workspace the strip has selected. `screens` builds one strip per monitor in a fixed order (main first: the chosen one, else an external monitor), `direction` says which way a workspace change goes (the overview slides its windows in from that side), and `dropPreview` works out what a drop would look like.

## Moving a window between workspaces

`OverviewCard` reports a drag (past a small threshold) as scene coordinates; `OverviewLayer` shows a ghost of the window, asks each `WorkspaceStrip` which workspace is under the pointer (`idAt`) and, on release, emits `moveRequested`; while dragging, `dropPreview` (via `previewFor`) feeds the strip under the pointer so it shows the new slot. `SnapLayouts` builds the Lua with `lib/dispatch.js` and sends it through `hyprctl eval`, then re-reads the state and re-lays-out. A workspace that does not exist yet would be created on the window's own monitor, so for an empty slot of another screen `moveToWorkspace` shows the workspace on its owner for a moment and then restores that monitor's view and the focused window.

## System look

The gap to the screen edge and the border width are read with `hyprctl -j getoption` on every snapshot and resolved by `lib/style.js` (unreadable answers fall back to defaults); zone geometry and the workspace thumbnails' usable area use them. Only the gap between snapped windows (`innerGap`, flush) is a plugin choice.

The overview backdrop (`Backdrop`) is deliberately not shaped like the windows: it lays the wallpaper over the whole screen the way the desktop does, paints only below the bar, and puts one dim over everything including the bar. Because it matches the real wallpaper pixel for pixel, nothing shows at its edges, so it needs no rounded corners.

## Shortcuts

The plugin binds its own keys, the way it already binds the drag buttons, and a product that is off binds none. `Settings.wantedShortcuts` says which: the layout keys while WinSaico is on (`layoutShortcut`, else the keys Omarchy has the layout cycle on, which `Shortcuts.layoutKeys` finds in `hyprctl -j binds` by their description, else Super+L and Super+Alt+L), the overview's key while the overview is on (`overviewShortcut`, else Alt+Tab), and the picker's `pickerShortcut` while Snapping is on. `ensureShortcutBinds` reads `hyprctl -j binds` and asks `Shortcuts.plan` what to do: bind what is wanted (`lua/shortcuts.lua`, tagging each bind with a description that carries its key; keys another bind holds are first cleared with `hl.unbind`, as Omarchy's `o.rebind` does, and the log says what was replaced, because a shortcut set on purpose belongs to the plugin and Omarchy's own Alt+Tab cycling would otherwise run along with the overview), and, when a bind of the plugin's no longer matches what is wanted, reload the config. That reload is also how a product switched off gives Omarchy's keys back. Hyprland 0.56.2 crashes on removing a bind, so the plugin only ever adds them; a reload clears runtime binds, and the `configreloaded` event brings the plugin back to bind what is wanted. It checks at start, when the options change, after a reload and every 30 seconds. The overview's key is also the one that closes the modal overview (`lua/overview-mode.lua` takes it as `snap_layouts_overview_shortcut`).

## WinSaico and auto-fit

**Why it is not Omarchy's floating mode.** Omarchy's floating mode (`o.workspace_mode` with `floating`, in `default/hypr/workspace-modes.lua`) floats every window that opens on the workspace through a window rule (64% by 68% of the monitor, centred, tagged), including a menu or popup that is a window of its own (Spotify's menu came out as a huge window), tags each window `omarchy-floating-workspace` so the title-bar plugin draws bars, and turns off focus-follows-mouse there. The layout picker (Super+Z) works because it does none of that: the workspace stays tiling and the plugin floats one window itself. WinSaico is built the same way. The workspace is in Omarchy's tiling layout and in the plugin's list, and `lua/mosaic.lua` (below) floats the windows that tile. Omarchy's `workspace_mode` is only used to put the workspace in tiling when WinSaico is entered from scrolling or floating (silently: `Dispatch.silentMode` makes the same call and writes the same file as the layout key but says nothing).

**Modes.** `lib/mode.js` knows the ring Super+L walks (tiling, scrolling, floating, mosaic) and how to reach a mode from what Omarchy reports: a workspace is mosaic when Omarchy has it in tiling and it is in the plugin's list (or the default is WinSaico and it is not in the plain-tiling list). `Mode.plan` returns the step (Omarchy's layout key to press, or none), whether the workspace is listed, whether it is plain tiling, whether the plugin must say the mode itself and what to do with the windows it floated (`release`: `tile` for tiling and scrolling, `claim` for floating, which tags them `omarchy-mode-floated` so Omarchy tiles them when floating ends). `Dispatch.layoutCommand` turns it into one shell command, in this order: the lists, the release, Omarchy's step, the placements, the announcement, the bar refresh. The announcement uses Omarchy's own sentences (`omarchy-i18n layout.workspaceTiling` and the like) for its modes and the plugin's (`i18n/<code>.json`, loaded with `Commons.Translations`) for WinSaico, in the notification Omarchy's layout commands share, so each replaces the last.

**The hook.** `lua/mosaic.lua` is loaded with `hyprctl eval` at start, after a config reload, and when the plugin is switched on or off (`snap_layouts.on`). It registers `window.open` and `window.move_to_workspace` once; reloading the file changes what they do without registering them again. On a workspace that is WinSaico (read from the plugin's files and Omarchy's saved layout, tiling underneath) a window that tiles is tagged `snap-layouts-floated`, floated and given Omarchy's usual size in the middle; a window that floats on its own account, is fullscreen or pinned is left alone, and a tagged window carried out to a workspace that is not WinSaico gives the floating up.

**Auto-fit** (`lib/autosnap.js`) works on floating windows, so everything is a size and a place and nothing tiles. On `openwindow`, `movewindowv2` and `closewindow` (only for a window the plugin placed: that is the only one that leaves a gap), if the workspace is in the list and `autoFit` is on, the plugin waits 25 ms (`fitDebounce`, only to catch a burst of events) for the window to settle, takes its own snapshot and asks `AutoSnap.plan`, which hands every window of the workspace a zone of `Layouts.mosaicZones` (the plugin's layouts for one to four windows, even rows past that) in the order they joined; `Dispatch.autoPlace` turns that into one `hyprctl eval` that floats (and tags), sizes and places without touching the focus. Who joins: windows the plugin placed before, windows carrying its tag (which outlives a restart of the shell), tiled ones, and, when the mode or auto-fit has just been switched on, every window (`adopt`). Dialogs and popups, which float on their own account, stay out. With auto-fit off, entering the mode floats the tiled windows where they are (`AutoSnap.keep`) and nothing else is touched.

**Speed** is a design constraint, with Omarchy's own layout key as the bar (one `hyprctl eval`, about 40 ms). Entering takes the snapshot first (about 17 ms for the six `hyprctl` reads), plans, and sends the mode change and the placements in one shell command, so windows move once from where they were to their places (measured: about 70 ms to the final geometry; a new window is in place about 45 ms after it appears; switching auto-fit on takes about 90 ms). The workspace is a mosaic one in memory from the start and the auto-fit switch forces its first fit (`fitForce`), so none of it waits for a file watcher or for the setting to come back from shell.json. Nothing polls: the hook is loaded on events and the only repeating timer is the bind check every 30 seconds.

**Default layout.** WinSaico can be the default layout. `defaultLayout winsaico` runs Omarchy's own default command for tiling and then writes a mark file (`snap-layouts-default`) that has to be newer than Omarchy's default file; the plugin watches that file and `Dispatch.staleMarkCommand` drops the mark when anything else rewrote it. With the mark on, `mosaicCheck` (on `workspacev2` and `openwindow`) asks Omarchy for a workspace's layout once and, if it tiles and is not in the plain-tiling list (`snap-layouts-plain`, kept by `layoutCommand`), adds it to the mosaic list and brings its windows in.

**The menu rows.** The row that sets this default is added to Appearance > Workspace Layout by `MenuRows`, with `lib/menu.js` editing the user's menu extension. Omarchy's menu merges rows by id but takes every field of a row the extension states (a row stating only `checked` would lose its label, icon and action), so the Tiling row has to be restated whole, with its label read from Omarchy's own catalog in the user's language, and with a tick that needs the mark to be absent (Omarchy sees WinSaico as tiling and would tick both). The two rows live between two marker comments, so the plugin can replace them (a new language) or remove them (WinSaico off, `uninstall`) without touching the rest of the file; rows a hand-made install of the earlier extras left are taken over. A file Omarchy's own reader would reject, or that the plugin cannot add to, is left as it is.

**The dock.** Omarchy's dock shows only on workspaces whose layout is floating and has no hook for anything else, so it does not show on WinSaico. A clone that also counted WinSaico was tried and dropped: a cloned plugin is handed a narrower shell (no `shellConfig`, no app library), so it loses the user's auto-hide, pins and the all-apps grid. The plugin uses Omarchy's dock as it is.

**Memory.** The records of who joined are kept in memory; after a restart of the shell, windows the plugin floated are recognised by their tag, others only rejoin when the mode or auto-fit is switched on again.

## Layers and notifications

Notifications live on the Overlay layer. The overview uses the Top layer so notifications stay above it, except when the active window is fullscreen, which hides the Top layer; there it falls back to Overlay.

## Adding a feature

Put the decision in `lib/` with a test first (`test/structure.test.js` will then check that the QML only calls what exists); add or extend a component for the view; wire both in `SnapLayouts.qml` (or, for something about WinSaico, in `controllers/WinSaico.qml`). If it needs a user option, add it to `lib/settings.js` with a default and a test, then document it in the README.
