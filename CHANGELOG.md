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

- The overview follows workspace changes made elsewhere (Super+1..5).
- The workspace strip is reachable with the arrow keys (Up from the top row, Down to return); Shift+Left/Right on it, or dragging a thumbnail onto another, swaps two workspaces' numbers; Enter or a double-click goes to one.
- The overview closes by running the windows back to their places; the wallpaper is decoded before the first frame, so it no longer pops in during the opening.
- Key handling for the overview moved to `lib/navigation.js` and is tested.

- The overview is modal: the system's shortcuts are paused while it is open (a Hyprland submap, `overview-mode.lua`), so Super+Shift+arrow can no longer swap, or carry to another monitor, the window behind it. Alt+Tab, Super+1..0, Super+Shift+arrow and Escape stay live, and so do screenshots and screen capture, notification keys and the volume, brightness and media keys; more can be added with `snap_layouts_overview_keep`. Super+Shift+arrow now swaps the selected window with its neighbour, or a workspace with its neighbour on the strip.

- Thumbnails take their colours from the theme, as Omarchy's image picker does: the accent ring marks what is selected; the workspace being looked at gets a softer accent ring while the windows have the focus and the strong one when the strip has it; everything else has a faint rim.
- One soft shadow (`RectangularShadow`) sized from the frame's height, so small thumbnails and large cards get the same look; the drag ghost uses the same frame.
- Smoother transition: a long-tailed opening curve and a symmetrical closing one, cards leaving their windows one after another with the selected one first, the workspace strip arriving last and leaving first (so a card returning to a full-screen mosaic window doesn't grow under it), the icon and title appearing only once a card has arrived, and a quick but eased dim.

Fixed
- Choosing a window (or pressing Enter on a workspace) while looking at a workspace that is not the one on screen no longer leaves its card parked in the middle of the screen, fading, while the real window is already showing: the workspace is about to be the visible one, so its cards now travel to their windows' real places like any other close.
- On closing, the selected card no longer overshoots its window, and nothing about the motion is tuned by hand to one layout: the card is enlarged and lifted only as far as the room around it inside the usable area allows (none for a window that fills the mosaic), and the workspace strip leaves before the first card heading back to its window would cross it, both computed from the windows' real rectangles in `lib/motion.js`. The remaining constants (durations, curves, stagger) are tokens in the same file.
- The overview backdrop is one piece: the wallpaper is laid out over the whole screen exactly as the desktop draws it (so it lines up across the bar), the part below the bar is painted, and a single dim covers everything, bar included. It reaches the screen edges, so the focused window's border can't show around it, and it has no corners of its own to show.
- Overview cards and workspace thumbnails share one frame (`ThumbFrame`): the same shadow, rounded clipping and a ring drawn above the content, so a picture can no longer spill over the outline. Workspace numbers are plain text instead of a badge.
- Workspace thumbnails show the usable area (without the bar and edge gap), so tiled windows fill them.
- The edge gap and border width are read from Hyprland (`lib/style.js`) instead of being written in the plugin, so a theme change is followed.
- Snap assist only offers windows of the workspace being filled.
- Snapped windows no longer leave a gap at the top on tiled workspaces: the title bar height is only added for windows on floating workspaces.
- Drag detection recognises tiled windows as well as floating ones.

Changed
- Tested on Omarchy 4.5.0; README install and uninstall steps cover the Alt+Tab binding, window limits, title bars and options.
- The code is split into `lib/` (pure logic, `npm test`), `components/` (views) and `SnapLayouts.qml` (state and Hyprland I/O).

## 0.1.0

Initial upstream release by n0rthstar88.
