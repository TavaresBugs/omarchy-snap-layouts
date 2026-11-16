# Changelog

## 0.2.0

Added
- Edge and corner snap: drag against the left or right edge for a half, a corner for a quarter, or the top edge for the whole usable area, with a preview and a short hold.
- Window overview (Alt+Tab style): thumbnails of the current workspace's windows in tidy rows, geometric arrow-key navigation, Enter or click to bring a window forward. A tiled window covered by floating windows is brought forward by tiling those floating windows.
- Workspace strip in the overview: the monitor's workspaces (Omarchy's per-monitor blocks), each showing its windows live, with Ctrl+Left/Right and PageUp/PageDown to switch the view.
- Drag a window thumbnail onto a workspace of the strip, or of the small strips for the other screens, to move it there. The workspace under the pointer previews the drop (the new slot, and the 50/50 split it causes), and a floating window dropped next to tiled ones is tiled.
- The strips keep a fixed order: the main screen big, the others small. The main screen defaults to an external monitor, and clicking a screen's name in the overview makes it the main one (saved as the `mainMonitor` option). Changing workspace in the overview slides the windows in instead of jumping.
- Options in `shell.json`: `edgeSnap`, `edgeDwellMs`, `edgeMargin`, `edgeCorner`, `overviewScope`.
- IPC: `overview` and `focus <address>`.
- Snap assist now uses the same thumbnails and row layout as the overview, in a quiet neutral frame, with paging. Number keys still pick a window, but no numbers are drawn.
- Optional Hyprland extras: key bindings and a floating-window limiter.

Fixed
- The overview backdrop follows the system's look: it reaches the screen edges (so the focused window's border can't show around it) and has the window corner curve, one gap further out. The bar strip is dimmed like the rest of the screen.
- Workspace thumbnails show the usable area (without the bar and edge gap), so tiled windows fill them.
- (Earlier in this release) the backdrop used the window rounding. Rounding, edge gap and border width are read from Hyprland (`lib/style.js`) instead of being written in the plugin, so a theme change is followed.
- Snap assist only offers windows of the workspace being filled.
- Snapped windows no longer leave a gap at the top on tiled workspaces: the title bar height is only added for windows on floating workspaces.
- Drag detection recognises tiled windows as well as floating ones.

Changed
- Tested on Omarchy 4.5.0; README install and uninstall steps cover the Alt+Tab binding, window limits, title bars and options.
- The code is split into `lib/` (pure logic, `npm test`), `components/` (views) and `SnapLayouts.qml` (state and Hyprland I/O).

## 0.1.0

Initial upstream release by n0rthstar88.
