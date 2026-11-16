-- The Hyprland side of WinSaico, for io.github.n0rthstar88.snap-layouts.
--
-- WinSaico is a workspace in Omarchy's tiling layout whose windows the plugin floats
-- itself, the way the layout picker (Super+Z) places a window. It is not Omarchy's
-- floating mode: that one floats every window that opens (a menu, a popup) at a set
-- size, draws a title bar on each and takes over focus. Here a window that tiles
-- when it opens is floated, tagged `snap-layouts-floated` (so the plugin can tell it
-- from windows that float on their own, and tile it again when the workspace leaves
-- the mode) and given a comfortable size in the middle; anything that floats by
-- itself (dialogs, popups, menus) is left exactly as it is. With auto-fit on the
-- plugin then moves the window to its place in the mosaic.
--
-- The plugin runs this with `hyprctl eval` at start, after a config reload (which
-- starts the Lua side afresh) and when it is switched on or off. Loading it again is
-- safe: the handlers are registered once and call the functions of this file as they
-- stand, so an updated file takes effect without a reload.

snap_layouts = snap_layouts or {}
local M = snap_layouts

-- The master switch: with the plugin off, windows are left alone.
M.on = true

local TAG = "snap-layouts-floated"

local DIR = (os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")) .. "/omarchy/"

local function read(name)
  local file = io.open(DIR .. name, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

-- Is this number in one of the plugin's files? One workspace number per line.
local function listed(name, id)
  local text = read(name)
  if not text then
    return false
  end
  for line in text:gmatch("[^\n]+") do
    if tonumber(line) == id then
      return true
    end
  end
  return false
end

-- The mode Omarchy has the workspace in: its own saved file, else the default's.
local function omarchy_mode(id)
  local own = read("workspace-layouts/" .. id .. ".lua")
  local mode = own and own:match('mode%s*=%s*"(%a+)"')
  if mode then
    return mode
  end
  local default = read("workspace-layouts/default.lua")
  return default and default:match('default%s*=%s*"(%a+)"') or "dwindle"
end

-- Is this workspace one the plugin has in WinSaico? Tiling underneath, and either in
-- the plugin's list or WinSaico is the default layout (a mark file) and the workspace
-- was not set to plain tiling on purpose.
local function mosaic(id)
  if not M.on or not id or id < 1 or omarchy_mode(id) ~= "dwindle" then
    return false
  end
  return listed("snap-layouts-workspaces", id)
    or (read("snap-layouts-default") ~= nil and not listed("snap-layouts-plain", id))
end

-- The same size and middle Omarchy's floating mode gives a window, stepped from the
-- last so windows opened one after another do not stack exactly on each other.
local cascade = 0

local function place(window)
  local monitor = window.monitor
  if not monitor or not monitor.width then
    return
  end

  local width = math.floor(monitor.width / monitor.scale)
  local height = math.floor(monitor.height / monitor.scale)
  if (monitor.transform or 0) % 2 == 1 then
    width, height = height, width
  end

  local reserved = monitor.reserved or {}
  width = width - (reserved.left or 0) - (reserved.right or 0)
  height = height - (reserved.top or 0) - (reserved.bottom or 0)

  hl.dispatch(hl.dsp.window.resize({
    x = math.min(1100, math.floor(width * 0.64)),
    y = math.min(760, math.floor(height * 0.68)),
    relative = false,
    window = window,
  }))
  hl.dispatch(hl.dsp.window.center({ window = window }))

  cascade = (cascade + 1) % 5
  hl.dispatch(hl.dsp.window.move({ x = cascade * 24 - 48, y = cascade * 24 - 48, relative = true, window = window }))
end

local function tagged(window)
  for _, tag in ipairs(window.tags or {}) do
    if tag == TAG or tag == TAG .. "*" then
      return true
    end
  end
  return false
end

-- A window that tiles on a WinSaico workspace is floated and placed. One that floats
-- on its own account, is fullscreen or is pinned is left alone. A window the plugin
-- floated that is carried out to a workspace that is not WinSaico gives that up, as
-- Omarchy's own floating mode does, rather than staying floating somewhere that tiles.
function M.float_in(window, workspace)
  local ws = workspace or window.workspace
  local id = ws and tonumber(ws.id)
  if not mosaic(id) then
    if M.on and id and id >= 1 and tagged(window) then
      hl.dispatch(hl.dsp.window.tag({ tag = "-" .. TAG, window = window }))
      hl.dispatch(hl.dsp.window.float({ action = "off", window = window }))
    end
    return
  end
  if window.floating or (window.fullscreen or 0) ~= 0 or window.pinned then
    return
  end
  hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = window }))
  hl.dispatch(hl.dsp.window.float({ action = "on", window = window }))
  place(window)
end

if not M.registered then
  M.registered = true

  hl.on("window.open", function(window)
    M.float_in(window)
  end)

  -- A move is still being committed when this fires, and changing the window's
  -- floating state underneath it would lose the move. Let it land first.
  hl.on("window.move_to_workspace", function(window, workspace)
    hl.timer(function()
      M.float_in(window, workspace)
    end, { type = "oneshot", timeout = 1 })
  end)
end
