# Changelog

## 0.2.0

Added
- Edge and corner snap: drag against the left or right edge for a half, a corner for a quarter, or the top edge for the whole usable area, with a preview and a short hold.
- Window overview (Alt+Tab style): thumbnails of the current workspace's windows in tidy rows, geometric arrow-key navigation, Enter or click to bring a window forward. A tiled window covered by floating windows is brought forward by tiling those floating windows.
- Workspace strip in the overview: the monitor's workspaces (Omarchy's per-monitor blocks), each showing its windows live, with Ctrl+Left/Right and PageUp/PageDown to switch the view.
- Options in `shell.json`: `edgeSnap`, `edgeDwellMs`, `edgeMargin`, `edgeCorner`, `overviewScope`.
- IPC: `overview` and `focus <address>`.
- Snap assist now uses the same thumbnails and row layout as the overview, in a quiet neutral frame, with number shortcuts and paging.
- Optional Hyprland extras: key bindings and a floating-window limiter.

Fixed
- Snapped windows no longer leave a gap at the top on tiled workspaces: the title bar height is only added for windows on floating workspaces.
- Drag detection recognises tiled windows as well as floating ones.

Changed
- The code is split into `lib/` (pure logic, `npm test`), `components/` (views) and `SnapLayouts.qml` (state and Hyprland I/O).

## 0.1.0

Initial upstream release by n0rthstar88.
