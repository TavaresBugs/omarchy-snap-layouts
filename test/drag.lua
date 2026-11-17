-- Tests for lua/drag.lua, run by test/drag.test.js with a plain Lua (there is no
-- Hyprland here): `hl` is a stub that holds the windows and the cursor and records the
-- events the file sends.
local windows, cursor, events, enabled = {}, { x = 0, y = 0 }, {}, false
local callback
hl = {
  get_windows = function() return windows end,
  get_cursor_pos = function() return cursor end,
  dsp = { event = function(text) return text end },
  dispatch = function(text) events[#events + 1] = text end,
  timer = function(fn)
    callback = fn
    return { set_enabled = function(_, on) enabled = on end }
  end,
}
dofile("lua/drag.lua")
local D = snap_layouts.drag
local PREFIX = "io.github.n0rthstar88.snap-layouts:drag:"

local failures = 0
local function check(name, cond)
  if not cond then
    failures = failures + 1
    print("FAIL: " .. name)
  end
end

local function window(address, x, y, w, h, fullscreen)
  return { address = address, at = { x = x, y = y }, size = { x = w, y = h }, fullscreen = fullscreen or 0 }
end

local function reset(list)
  windows, events = list, {}
  cursor = { x = 100, y = 100 }
end

-- the one that moved without changing size is the dragged one
do
  local base = D.positions({ window("0xa", 0, 0, 500, 400), window("0xb", 600, 0, 500, 400) })
  check("nothing moved", D.mover(base, { window("0xa", 0, 0, 500, 400), window("0xb", 600, 0, 500, 400) }) == nil)
  check("jitter is not a drag", D.mover(base, { window("0xa", 3, 4, 500, 400) }) == nil)
  check("moved", D.mover(base, { window("0xa", 0, 0, 500, 400), window("0xb", 700, 0, 500, 400) }) == "0xb")
  check("resized is not dragged", D.mover(base, { window("0xa", 50, 0, 450, 400) }) == nil)
  check("fullscreen is not dragged", D.mover(base, { window("0xa", 50, 50, 500, 400, 2) }) == nil)
  check("a window that was not there is not dragged", D.mover(base, { window("0xc", 50, 50, 500, 400) }) == nil)
end

-- a drag: silent until a window moves, then one event per change of position
do
  reset({ window("0xa", 0, 0, 500, 400) })
  D.start()
  check("start turns the timer on", enabled)
  callback()
  check("no window has moved: nothing is sent", #events == 0)
  windows[1] = window("0xa", 40, 30, 500, 400)
  cursor = { x = 140.9, y = 130.2 }
  callback()
  check("the window and the pointer are sent", events[1] == PREFIX .. "0xa,140,130")
  callback()
  check("a pointer held still sends nothing", #events == 1)
  cursor = { x = 150, y = 130 }
  callback()
  check("a new position is sent", events[2] == PREFIX .. "0xa,150,130")
  D.stop()
  check("stop turns the timer off", not enabled)
  callback()
  check("a look after the stop sends nothing", #events == 2)
end

-- a click: nothing moves, so after a while it says so and stops
do
  reset({ window("0xa", 0, 0, 500, 400) })
  D.start()
  for _ = 1, 400 do callback() end
  check("it gave up", events[#events] == PREFIX .. "idle" and not enabled)
  check("and said so once", #events == 1)
end

-- a drag that goes on past the limit (the release was lost) is stopped too
do
  reset({ window("0xa", 0, 0, 500, 400) })
  D.start()
  windows[1] = window("0xa", 40, 30, 500, 400)
  for i = 1, 8000 do
    cursor = { x = i, y = 0 }
    callback()
    if not enabled then break end
  end
  check("the limit stops it", not enabled and events[#events] == PREFIX .. "idle")
end

-- loading the file again keeps the one timer and the state
do
  local before = D.timer
  dofile("lua/drag.lua")
  check("the timer is made once", snap_layouts.drag.timer == before)
end

if failures > 0 then
  os.exit(1)
end
print("ok")
