
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
--   Alt+Tab (or your overviewShortcut)  closes the overview
--   Super+Shift+arrow        swap: a workspace on the strip, a window on the cards
--   Super+1 .. Super+0       switch workspace, as Omarchy does; the overview follows
--   Escape                   leaves the submap (Hyprland resets it); the plugin
--                            sees that and closes, so Escape is always a way out
--   KEEP below               screenshots and screen capture, notification keys,
--                            volume, brightness and media keys, so the overview
--                            can be captured and the hardware keys keep working
--
-- The plugin leaves the submap itself when the overview closes, and resets it if
-- it starts up while the submap is still active.

local PLUGIN = "io.github.n0rthstar88.snap-layouts:"

-- Hyprland keeps a submap's binds until its config is reloaded, and defining a
-- name again would add them a second time. So the name carries a version: bump
-- it whenever the binds below change, and the new definition is used at once.
local VERSION = 5

-- The key that closes the overview: the plugin's overviewShortcut option when it
-- is set (the plugin passes it in), Alt+Tab otherwise. It is part of the name, so
-- a different key gets its own definition.
local EXIT = snap_layouts_overview_shortcut or "ALT + TAB"
local SUBMAP = "snap_layouts_overview_v" .. VERSION .. "_" .. EXIT:gsub("[^%w]", "_")

-- System shortcuts that stay live while the overview is open: { keys, description,
-- action, options }. They are bound with Omarchy's own `o.bind`, so an action means
-- exactly what it does on the desktop. This mirrors Omarchy's defaults; if you have
-- changed a shortcut, or want another to stay live, add it to a global
-- `snap_layouts_overview_keep` in your Hyprland config, in the same shape:
--   snap_layouts_overview_keep = { { "SUPER + SPACE", "Omarchy menu", { menu = "root" } } }
local LOCKED = { locked = true }
local REPEAT = { locked = true, repeating = true }
local KEEP = {
  -- Screenshots and screen capture
  { "SUPER + CTRL + C", "Capture menu", { menu = "capture" } },
  { "PRINT", "Screenshot", "omarchy-capture-screenshot" },
  { "SUPER + CTRL + ALT + C", "Screenshot", "omarchy-capture-screenshot" },
  { "ALT + PRINT", "Screenrecording", "omarchy-capture-screenrecording --stop-recording || omarchy-menu toggle trigger.capture.screenrecord" },
  { "SUPER + PRINT", "Color picker", "pkill hyprpicker || hyprpicker -a" },
  { "SUPER + CTRL + PRINT", "Extract text (OCR) from screenshot", "omarchy-capture-text" },
  -- Notifications
  { "SUPER + comma", "Dismiss, invoke, or focus last notification", { ipc = "notifications.act" } },
  { "SUPER + SHIFT + comma", "Dismiss all notifications", { ipc = "notifications.dismissAll" } },
  { "SUPER + ALT + comma", "Dismiss last notification", { ipc = "notifications.dismissOne" } },
  -- Volume, brightness and media
  { "XF86AudioRaiseVolume", "Volume up", { audio = "raise" }, REPEAT },
  { "XF86AudioLowerVolume", "Volume down", { audio = "lower" }, REPEAT },
  { "XF86AudioMute", "Mute", { audio = "mute-toggle" }, LOCKED },
  { "XF86AudioMicMute", "Mute microphone", "omarchy-audio-input-mute", LOCKED },
  { "XF86MonBrightnessUp", "Brightness up", { brightness = "raise" }, REPEAT },
  { "XF86MonBrightnessDown", "Brightness down", { brightness = "lower" }, REPEAT },
  { "XF86AudioNext", "Next track", { ipc = "media.next" }, LOCKED },
  { "XF86AudioPause", "Pause", { ipc = "media.playPause" }, LOCKED },
  { "XF86AudioPlay", "Play", { ipc = "media.playPause" }, LOCKED },
  { "XF86AudioPrev", "Previous track", { ipc = "media.previous" }, LOCKED },
}

snap_layouts_overview_submaps = snap_layouts_overview_submaps or {}

if not snap_layouts_overview_submaps[SUBMAP] then
  snap_layouts_overview_submaps[SUBMAP] = true

  local function report(name)
    return function()
      hl.dispatch(hl.dsp.event(PLUGIN .. name))
    end
  end

  hl.define_submap(SUBMAP, "escape", function()
    hl.bind(EXIT, report("overview"), { description = PLUGIN .. "overview" })

    for _, direction in ipairs({ "left", "right", "up", "down" }) do
      hl.bind("SUPER + SHIFT + " .. direction, report("swap-" .. direction), { description = PLUGIN .. "swap" })
    end

    for slot = 1, 10 do
      local go = (o and o.workspaces) and o.workspaces.focus(slot) or hl.dsp.focus({ workspace = tostring(slot) })
      hl.bind("SUPER + " .. tostring(slot % 10), go, { description = PLUGIN .. "workspace" })
    end

    if o and o.bind then
      local function keep(list)
        for _, entry in ipairs(list or {}) do
          -- A bad entry must not take the others, or the overview, down with it.
          pcall(o.bind, entry[1], entry[2], entry[3], entry[4] and { locked = entry[4].locked, repeating = entry[4].repeating })
        end
      end
      keep(KEEP)
      keep(snap_layouts_overview_keep)
    end
  end)
end

-- Entering in the same breath as defining the submap does not always take, so
-- check, and try once more a moment later if it did not.
hl.dispatch(hl.dsp.submap(SUBMAP))
if hl.get_current_submap() ~= SUBMAP then
  hl.timer(function()
    hl.dispatch(hl.dsp.submap(SUBMAP))
  end, { type = "oneshot", timeout = 50 })
end
