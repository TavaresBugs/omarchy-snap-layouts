
-- Makes the window overview modal, for io.github.n0rthstar88.snap-layouts.
--
-- The plugin runs this with `hyprctl eval` each time the overview opens. Until
-- the overview closes the system's own shortcuts are paused, so a key meant for
-- the overview can't also act on the windows behind it (Super+Shift+arrow would
-- otherwise swap, and even carry to the other monitor, the window you can't
-- see). Hyprland does that with a submap: only the binds defined in it are
-- live, and every other key goes on to the overview.
--
-- What stays live is reported to the plugin as events, or does what it always
-- does:
--   Alt+Tab                  closes the overview
--   Super+Shift+arrow        swap: a workspace on the strip, a window on the cards
--   Super+1 .. Super+0       switch workspace, as Omarchy does; the overview follows
--   Escape                   leaves the submap (Hyprland resets it); the plugin
--                            sees that and closes, so Escape is always a way out
--
-- The plugin leaves the submap itself when the overview closes, and resets it if
-- it starts up while the submap is still active.

local PLUGIN = "io.github.n0rthstar88.snap-layouts:"
local SUBMAP = "snap_layouts_overview"

if not snap_layouts_overview_defined then
  snap_layouts_overview_defined = true

  local function report(name)
    return function()
      hl.dispatch(hl.dsp.event(PLUGIN .. name))
    end
  end

  hl.define_submap(SUBMAP, "escape", function()
    hl.bind("ALT + TAB", report("overview"), { description = PLUGIN .. "overview" })

    for _, direction in ipairs({ "left", "right", "up", "down" }) do
      hl.bind("SUPER + SHIFT + " .. direction, report("swap-" .. direction), { description = PLUGIN .. "swap" })
    end

    for slot = 1, 10 do
      local go = (o and o.workspaces) and o.workspaces.focus(slot) or hl.dsp.focus({ workspace = tostring(slot) })
      hl.bind("SUPER + " .. tostring(slot % 10), go, { description = PLUGIN .. "workspace" })
    end
  end)
end

hl.dispatch(hl.dsp.submap(SUBMAP))
