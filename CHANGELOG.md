# Changelog

## 0.2.0

The first release of this fork. Built on 0.1.0 by n0rthstar88.

### Added

Snapping
- Edge and corner snap: drag against the left or right edge for a half, a corner for a quarter, or the top edge for the whole usable area, with a preview and a short hold.
- Snap assist offers only the windows of the workspace being filled, in the same thumbnails and row layout as the overview, in a quiet neutral frame, with paging.

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
- Options in `shell.json`: `edgeSnap`, `edgeDwellMs`, `edgeMargin`, `edgeCorner`, `overviewScope`, `mainMonitor`.
- IPC: `overview` and `focus <address>`.
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
