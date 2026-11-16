# Hyprland extras

Optional Hyprland configuration that goes well with the plugin. Nothing here is needed for the plugin itself.

## Key bindings

Add to `~/.config/hypr/bindings.lua`:

```lua
-- Layout picker for the focused window
o.bind("SUPER + Z", "Snap layouts", hl.dsp.event("io.github.n0rthstar88.snap-layouts:toggle"))

-- Window overview: every window of the current workspace, pick one to bring forward
o.bind("ALT + TAB", "Window overview", hl.dsp.event("io.github.n0rthstar88.snap-layouts:overview"))
```

Reload with `hyprctl reload` and check `hyprctl configerrors`.

## Window limits

[`window-limits.lua`](window-limits.lua) stops floating windows from being dragged above the top bar, off the sides or bottom, or resized larger than the usable area.

```sh
cp window-limits.lua ~/.config/hypr/window-limits.lua
```

Then add `require("hypr.window-limits")` to `~/.config/hypr/hyprland.lua`, after the other `require` lines, and run `hyprctl reload`.

It checks floating windows 20 times a second and only acts on a window that has stopped moving while no mouse button is held, so dragging is never fought; a window dragged past the edge slides back when you let go. To turn it off, remove the `require` line.
