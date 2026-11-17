-- The pointer while a window is dragged, for io.github.n0rthstar88.snap-layouts.
--
-- Hyprland has no event for "the window is being moved", and asking for the cursor and
-- the windows with `hyprctl` from the shell costs two processes per look (60 to 90 ms
-- late, in practice). Inside Hyprland the same look takes microseconds, so this file
-- looks from here, and only tells the plugin what it saw:
--
--   <plugin id>:drag:<address>,<x>,<y>   the window being dragged, and where the pointer is
--   <plugin id>:drag:idle                nothing moved, so there is no drag: stopped
--
-- It decides nothing about zones, edges or previews; that is lib/drag.js, which also
-- owns the clock. The sample is sent when it differs from the last, so a pointer held
-- still sends nothing.
--
-- The plugin starts it on a button press and stops it on the release, with
-- `hyprctl eval` (`dofile` of this file, then snap_layouts.drag.start() or .stop()).
-- Loading the file again is safe: the timer is made once and calls the functions as
-- they stand, so an updated file takes effect without a reload. It also never outlives
-- a drag if the release is lost: it stops by itself, see IDLE and LIMIT.

snap_layouts = snap_layouts or {}
snap_layouts.drag = snap_layouts.drag or {}
local D = snap_layouts.drag

local EVENT = "io.github.n0rthstar88.snap-layouts:drag:"

local INTERVAL = 8   -- ms between looks while a button is held
local MOVED = 4      -- px a window must travel to count as moved (jitter is not a drag)
local IDLE = 1500    -- ms after the press with no window moving: it was a click, give up
local LIMIT = 60000  -- ms: a drag this long means the release was lost

-- Where every window is: { [address] = { x, y, width, height } }.
function D.positions(windows)
  local map = {}
  for _, window in ipairs(windows) do
    map[window.address] = { window.at.x, window.at.y, window.size.x, window.size.y }
  end
  return map
end

-- The window that has moved without changing size since `base`: the one being dragged,
-- by its title bar, with Super held, or by another plugin's drag. A window that was
-- resized is not being dragged; a fullscreen one is not either.
function D.mover(base, windows)
  for _, window in ipairs(windows) do
    local was = base[window.address]
    if was and (window.fullscreen or 0) == 0
        and window.size.x == was[3] and window.size.y == was[4]
        and (math.abs(window.at.x - was[1]) > MOVED or math.abs(window.at.y - was[2]) > MOVED) then
      return window.address
    end
  end
  return nil
end

local function say(text)
  hl.dispatch(hl.dsp.event(EVENT .. text))
end

function D.start()
  D.base = D.positions(hl.get_windows())
  D.address = nil
  D.last = nil
  D.looks = 0
  D.timer:set_enabled(true)
end

function D.stop()
  D.timer:set_enabled(false)
  D.base = nil
end

-- One look: called by the timer while a button is held.
function D.tick()
  if not D.base then
    D.timer:set_enabled(false)
    return
  end
  -- Time is counted in looks, so it needs no clock; a late timer only makes it longer.
  D.looks = D.looks + 1
  local held = D.looks * INTERVAL
  if held > LIMIT or (not D.address and held > IDLE) then
    D.stop()
    say("idle")
    return
  end
  if not D.address then
    D.address = D.mover(D.base, hl.get_windows())
    if not D.address then
      return
    end
  end
  local ok, cursor = pcall(hl.get_cursor_pos)
  if not ok or not cursor then
    return
  end
  local text = D.address .. "," .. math.floor(cursor.x) .. "," .. math.floor(cursor.y)
  if text ~= D.last then
    D.last = text
    say(text)
  end
end

if not D.registered then
  D.registered = true
  D.timer = hl.timer(function()
    D.tick()
  end, { timeout = INTERVAL, type = "repeat" })
  D.timer:set_enabled(false)
end
