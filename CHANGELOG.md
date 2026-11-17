# Changelog

## 0.3.0

WinSaico, and the plugin's three products each with a switch of their own.

### Added

WinSaico
- A fourth workspace layout in Omarchy's Super+L cycle (tiling, scrolling, floating, WinSaico) and in Appearance > Workspace Layout: free windows that share the screen. It is a workspace in Omarchy's tiling layout whose windows the plugin floats itself, as the picker does, so a menu or popup stays the size it asks for and windows have no title bar. It is deliberately not Omarchy's floating mode, which floats everything that opens at a set size, adds title bars and takes over focus.
- **Auto fit**, its complement (`autoFit`, `omarchy-shell snaplayouts autofit on|off|toggle|status`, a key with `autoFitShortcut`): the windows share the screen in the plugin's layouts, a new one takes its place and the others make room; with it off a new window opens in front and in the middle.
- The plugin takes the layout keys from wherever Omarchy has them, and gives them back when WinSaico is off. `omarchy-shell snaplayouts layout next|back|tiling|scrolling|floating|winsaico` sets the mode by command.
- WinSaico's row in the layout menu is written to the user's menu extension, in a marked block, while WinSaico is on, and removed when it is off. A workspace that tiles by default joins the mosaic the first time it is shown or gets a window, unless it was set to plain tiling on purpose.
- Entering WinSaico says "Workspace layout set to WinSaico" in Omarchy's own words and language (`i18n/`), replacing the previous notification as Omarchy's do.
- As quick as Omarchy's own modes: entering with auto-fit on moves the windows once, in about 0.1 s; a new window is in its place 50 ms after it appears and a closed one's gap closes in about 60 ms.
- A small Hyprland hook (`lua/mosaic.lua`) floats a window that tiles when it opens on a WinSaico workspace and leaves dialogs, popups and menus alone; the windows it floated carry the tag `snap-layouts-floated` so leaving the mode tiles them again.

Three products, three switches
- The bar card is **WinSaico** (for the workspace on screen, with Auto fit beneath it), **Alt+Tab** and **Snapping**. `omarchy-shell snaplayouts product winsaico|overview|snap on|off|toggle|status`.
- `omarchy-shell snaplayouts uninstall` turns every product off, removes WinSaico's menu rows and forgets the plugin's state files, before `omarchy plugin remove`.
- The code is split: `controllers/` (the options both entry points read, WinSaico with auto-fit, the menu rows), `lua/` (what runs in Hyprland), `lib/menu.js`, `lib/hyprctl.js`.

### Changed

- Dragging a window to an edge is quicker to recognise. The pointer is read inside Hyprland (`lua/drag.lua`, started by `controllers/DragSensor.qml`) instead of by running `hyprctl` twice every 60 ms, and the rules that turn it into a preview or the picker are a library of their own (`lib/drag.js`, tested). The wait at an edge (`edgeDwellMs`) is 120 ms by default (was 320) and a corner reaches 60 px along an edge (`edgeCorner`, was 90). Set the old values in `shell.json` to get the old feel back.
- The options are `winsaico`, `overview` and `snap` in place of `enabled`, `dragToSnap` and `edgeSnap`. An entry from 0.2.0 still reads right and is rewritten in the new form by the first change saved from the card.
- The overview is off until it is switched on, because it replaces Alt+Tab; the plugin's default key is Alt+Tab (`overviewShortcut` changes it).
- The one-time prompt about drag-to-snap is gone: Snapping is on from the start and the card turns it off.
- No clone of Omarchy's dock or workspaces widget is shipped: a cloned plugin gets a narrower shell (no `shellConfig`, no app library), so a clone loses the user's settings. The dock stays Omarchy's own and shows on floating workspaces only.
- The overview leaves the bar to the bar. The bar is not covered or dimmed, it takes clicks as usual (the workspaces, the clock, the tray) and what it shows follows what the overview does: clicking a workspace in the bar makes the overview show it, and moving along the overview's workspace strip changes the workspace for real, so the bar and the strip always agree. Escape (or leaving the overview any other way than choosing something) puts the monitor back on the workspace it was on. Hyprland sends all pointer input to a layer that holds the keyboard exclusively, the bar's strip included, so the overview lets go of the keyboard while the pointer is on the bar and takes it back when it comes down.
- The overview's backdrop is the wallpaper blurred (`components/Wallpaper.qml`), with no dark shade over it, instead of a black dim. The strip behind the bar, a surface on the Bottom layer under the bar, draws the same blurred wallpaper, so whatever the bar is (clear, glassy or solid) it sits on the picture the backdrop shows and the two meet without a seam, and the bar is never forced into another look (changing it rewrites `shell.json` and reloads Hyprland). The monitor names sit on a small glass chip (the theme's background, see-through, with the theme's text on it) and a card's title has an outline, to stay readable on a bright wallpaper.

### Fixed

- Choosing a window in the Alt+Tab overview brings it forward even when a floating window such as a browser covers it. The overview holds the keyboard exclusively while it is open, and Hyprland ignores a focus request until it lets go, so the focus stayed on the old window and returned to it when the overview closed. Now the cards travel back to their windows, the overview lets go of the keyboard, asks for the focus and goes away when Hyprland says it has moved.
- The overview card of the selected window no longer jumps when the overview goes away. It was drawn 5% larger than the window even once it sat on it (when the window has room around it, as a floating one does), and showed its ring and rounded corners there; now the enlargement, the lift, the ring and the corners grow with the card's travel, so on its window it is that window exactly.
- A thin line no longer crosses the screen under the bar while the overview is open. The dimmed wallpaper started at the bar's bottom edge, which is rarely a whole number of pixels, and the accent of the focused window's border showed through the row left between; it now starts a pixel higher.
- A light picture no longer shows a pixel beyond the corner of a card's ring (seen on a light theme, a white fringe at the corners of a card with a bright window): the content's mask is a pixel smaller than the frame, under the ring that covers it.
- The overview no longer leaves a ghost of its last frame over the window it has just chosen. Hyprland faded the overlay out over about 150 ms, drawing a card (with its ring, its shadow and a capture a moment old) over the real window; `lua/layer.lua` turns that fade off for the plugin's layer, as Omarchy's own panels do.

### Removed

- The master switch (`enabled`, `power`) and the `drag` command, replaced by the three switches and `product`.

## 0.2.0

The first release of this fork. Built on 0.1.0 by n0rthstar88.

### Added

Snapping
- Edge and corner snap: drag against the left or right edge for a half, a corner for a quarter, or the top edge for the whole usable area, with a preview and a short hold.
- Snap assist offers only the windows of the workspace being filled, in the same thumbnails and row layout as the overview, with paging. It sits on the same frosted wallpaper as the overview instead of a black shade, with the windows already placed shown in their zones.
- Every corner the plugin draws comes from one rule (`lib/shape.js`), from the windows' own rounding: a placed window's picture and the zone outline have exactly a window's corners, cards and the workspace thumbnails are a step rounder, the layout picker a step more. A card goes from its window's corners to the card's as it travels, so it no longer starts square.
- What taste decides is named and kept in the libraries, not written in the components: ring thickness (`Shape.ring`, from the windows' real border), how strong each tint is by role (`Shape.ALPHA`), where the assist's cards go (`Shape.panelArea`, from the theme's spacing) and how long the small animations take (`Motion.TOKENS.dur`), which now go through `Style.duration` so they stop when the system has animations off. A test fails if a component writes a radius, a duration or a tint strength as a number.
- In the snap assist, a window already placed is framed like an overview card: the same ring, accent for the one just placed, drawn around the window with its coloured border (`Layouts.frameRect`) instead of around the window alone.

Window overview (Alt+Tab)
- Thumbnails of the current workspace's windows in tidy rows, geometric arrow-key navigation, Enter or click to bring a window forward. A tiled window covered by floating windows is brought forward by tiling those floating windows.
- Opening runs the real windows into the thumbnails and closing runs them back, with cards leaving one after another, the selected one first. The selected card is enlarged only as far as the room around it allows, and the workspace strip leaves before a card heading back to its window would cross it. Both are computed from the windows' real rectangles; the remaining tuning is a handful of tokens in `lib/motion.js`.
- Modal: the system's shortcuts are paused while it is open (a Hyprland submap, `overview-mode.lua`), so Super+Shift+arrow can no longer swap, or carry to another monitor, the window behind it. Alt+Tab, Super+1..0, Super+Shift+arrow, Escape, screenshots and screen capture, notification keys and the volume, brightness and media keys stay live; more can be added with `snap_layouts_overview_keep`.
- Super+Shift+arrow swaps the selected window with its neighbour in the real layout.

Workspace strip
- One strip per screen, following Omarchy's per-monitor blocks, each workspace showing its windows live. The main screen is big and the others small, in a fixed order; it defaults to an external monitor, and clicking a screen's name makes it the main one (saved as `mainMonitor`).
- Look at a workspace (click, Ctrl+Left/Right, PageUp/PageDown; the overview also follows Super+1..5), go to one (double-click or Enter), reach the strip with the arrow keys.
- Drag a window thumbnail onto any workspace to move the window there; the thumbnail previews the drop, including the 50/50 split, and a floating window dropped next to tiled ones is tiled.
- Swap two workspaces' numbers: drag a thumbnail onto another, or Shift+Left/Right (or Super+Shift+Left/Right) on the strip.

Look
- Thumbnails take their colours from the theme, as Omarchy's image picker does: the accent ring marks the selection, a softer accent ring the workspace being looked at, a faint rim the rest. One soft shadow, sized from the frame, gives small thumbnails and large cards the same look (`ThumbFrame`).
- The backdrop is one piece: the wallpaper laid out over the whole screen exactly as the desktop draws it, one dim over everything including the bar, reaching the screen edges.

Configuration
- Shortcuts without editing `bindings.lua`: `omarchy-shell snaplayouts shortcut picker "SUPER + Z"` (and `overview`) saves the shortcut and the plugin binds it, taking the keys over from whatever else is bound there (Omarchy's Alt+Tab cycling, say) and logging what it replaced, and reloading the config only when one is changed or removed. The key that closes the overview follows `overviewShortcut`.
- Options in `shell.json`: `edgeSnap`, `edgeDwellMs`, `edgeMargin`, `edgeCorner`, `overviewScope`, `mainMonitor`, `pickerShortcut`, `overviewShortcut`.
- IPC: `overview`, `focus <address>` and `shortcut <picker|overview> <keys|off>`.
- Optional Hyprland extras: key bindings and a floating-window limiter.

### Changed
- The code is split into `lib/` (pure logic, tested with `npm test`), `components/` (views) and `SnapLayouts.qml` (state and Hyprland I/O); see `docs/ARCHITECTURE.md`.
- The gap to the screen edge and the border width are read from Hyprland instead of being written in the plugin.
- Tested on Omarchy 4.5.0.

### Fixed
- Snapped windows no longer leave a gap at the top on tiled workspaces: the title bar height is only added for windows on floating workspaces.
- Drag detection recognises tiled windows as well as floating ones.

## 0.1.0

Initial upstream release by n0rthstar88.
