-- The overlay's layer rule, for io.github.n0rthstar88.snap-layouts.
--
-- The overlay (the picker, the edge preview, the overview) animates itself. Hyprland
-- also fades a layer surface out when it goes away, by default over about 150 ms, and
-- what it fades is the last frame of the overlay: a card that has just landed on its
-- window, with its ring and its shadow and a capture of the window that is a moment
-- old. For those 150 ms it is drawn over the real window, which shows twice. Omarchy's
-- own panels turn the fade off for the same reason (default/hypr/apps/omarchy-shell.lua).
--
-- The plugin runs this with `hyprctl eval` at start and after a config reload, which
-- starts the Lua side afresh and drops runtime rules. Loading it again is safe.

snap_layouts = snap_layouts or {}

if not snap_layouts.layer_rule then
  snap_layouts.layer_rule = true
  hl.layer_rule({ match = { namespace = "^snap-layouts$" }, no_anim = true, animation = "none" })
end
