
-- Binds the plugin's own shortcuts, for io.github.n0rthstar88.snap-layouts.
--
-- The plugin runs this with `hyprctl eval` when the shortcuts set in its options
-- (pickerShortcut, overviewShortcut) are missing from `hyprctl binds`: at start,
-- after a config reload wipes runtime binds, or when an option changes. It sets
-- snap_layouts_shortcuts to { picker = "SUPER + Z", ... } first, holding only
-- the ones to bind now, and snap_layouts_shortcuts_replace to { picker = true }
-- for those whose keys something else holds. A shortcut set on purpose belongs to
-- the plugin, so those keys are first cleared (hl.unbind, as Omarchy's o.rebind
-- does): Omarchy's own Alt+Tab cycling would otherwise run along with the overview.
--
-- Each bind carries a description with its key, which is how the plugin later
-- recognises it. Never call remove() on these (see hook.lua): changing a
-- shortcut is done by reloading the config and binding again.

local PLUGIN = "io.github.n0rthstar88.snap-layouts:"
local EVENTS = { picker = "toggle", overview = "overview" }

for name, spec in pairs(snap_layouts_shortcuts or {}) do
  local event = EVENTS[name]
  if event then
    if (snap_layouts_shortcuts_replace or {})[name] then
      hl.unbind(spec)
    end
    hl.bind(spec, hl.dsp.event(PLUGIN .. event), {
      description = PLUGIN .. "shortcut:" .. name .. ":" .. spec,
    })
  end
end

snap_layouts_shortcuts = nil
snap_layouts_shortcuts_replace = nil
