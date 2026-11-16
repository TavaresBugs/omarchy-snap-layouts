-- Keep floating windows inside the usable area of their monitor.
--
-- No floating window can end up above the top bar, outside the screen sides or
-- bottom, or larger than the usable area. The border width is kept clear so the
-- border is never hidden under the bar. Tiled windows, fullscreen windows and
-- special workspaces are left alone.
--
-- A window is only corrected once it has stopped moving and no mouse button is
-- held, so dragging and resizing are never fought: it slides back when released.
--
-- Install: copy to ~/.config/hypr/window-limits.lua and add to hyprland.lua:
--   require("hypr.window-limits")

local INTERVAL_MS = 50
local TOLERANCE = 1 -- pixels of difference that are not worth correcting

-- Number of mouse buttons (left, right) currently held.
local buttons_held = 0
-- "x,y,w,h" of each window at the previous tick, to tell when it has stopped.
local last_geometry = {}

for _, button in ipairs({ "mouse:272", "mouse:273" }) do
  hl.bind(button, function() buttons_held = buttons_held + 1 end,
    { non_consuming = true, ignore_mods = true, description = "window-limits: button pressed" })
  hl.bind(button, function() buttons_held = math.max(0, buttons_held - 1) end,
    { release = true, non_consuming = true, ignore_mods = true, description = "window-limits: button released" })
end

local function has_settled(window)
  local geometry = string.format("%d,%d,%d,%d", window.at.x, window.at.y, window.size.x, window.size.y)
  local same = last_geometry[window.address] == geometry
  last_geometry[window.address] = geometry
  return same
end

local function clamp_to_usable_area(window)
  if not window.floating or (window.fullscreen or 0) ~= 0 then return end
  if buttons_held > 0 or not has_settled(window) then return end

  local workspace = window.workspace
  if not workspace or tonumber(workspace.id) == nil or tonumber(workspace.id) < 1 then return end

  local monitor = window.monitor
  if not monitor or not monitor.width then return end

  local scale = monitor.scale or 1
  local width, height = monitor.width / scale, monitor.height / scale
  if (monitor.transform or 0) % 2 == 1 then width, height = height, width end

  -- The border is drawn outside the window, so keep its width free on every
  -- side; otherwise it would hide under the bar.
  local reserved = monitor.reserved or {}
  local border = tonumber(hl.get_config("general.border_size")) or 2
  local left = monitor.x + (reserved.left or 0) + border
  local top = monitor.y + (reserved.top or 0) + border
  local usable_w = width - (reserved.left or 0) - (reserved.right or 0) - 2 * border
  local usable_h = height - (reserved.top or 0) - (reserved.bottom or 0) - 2 * border

  local new_w = math.min(window.size.x, usable_w)
  local new_h = math.min(window.size.y, usable_h)
  local new_x = math.max(left, math.min(window.at.x, left + usable_w - new_w))
  local new_y = math.max(top, math.min(window.at.y, top + usable_h - new_h))

  local selector = "address:" .. window.address
  if math.abs(new_w - window.size.x) > TOLERANCE or math.abs(new_h - window.size.y) > TOLERANCE then
    hl.dispatch(hl.dsp.window.resize({ x = math.floor(new_w), y = math.floor(new_h), window = selector }))
  end
  if math.abs(new_x - window.at.x) > TOLERANCE or math.abs(new_y - window.at.y) > TOLERANCE then
    hl.dispatch(hl.dsp.window.move({ x = math.floor(new_x), y = math.floor(new_y), window = selector }))
  end
end

hl.timer(function()
  for _, window in ipairs(hl.get_windows()) do
    pcall(clamp_to_usable_area, window)
  end
end, { timeout = INTERVAL_MS, type = "repeat" })
