-- A cell-based tiling layout for Omarchy's Hyprland Lua configuration.
-- Part of https://github.com/MrSlothuus/matrix.grid (MIT); install.sh links
-- this file to ~/.config/hypr/cellgrid.lua.
-- These are defaults: the Grid panel in the bar changes them and saves its
-- choices to settings_path, which wins on every reload.
local columns = 8
local minimum_rows = 8
local new_window_width, new_window_height = 3, 3
local grid_enabled = true
local show_handles = true
local fallback_layout = "dwindle"
local grid_limit = 16

local workspaces = {}
local pending_window = nil

local function clamp(value, low, high)
  return math.max(low, math.min(value, high))
end

local settings_path = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
  .. "/omarchy/cellgrid-settings.lua"

local function load_settings()
  -- An empty environment keeps the saved file to plain data.
  local chunk = loadfile(settings_path, "t", {})
  local ok, saved = pcall(chunk or function() end)
  if not ok or type(saved) ~= "table" then
    return
  end
  local function whole(value, low, high, fallback)
    return math.type(value) == "integer" and clamp(value, low, high) or fallback
  end
  columns = whole(saved.columns, 2, grid_limit, columns)
  minimum_rows = whole(saved.rows, 2, grid_limit, minimum_rows)
  new_window_width = whole(saved.new_width, 1, columns, math.min(new_window_width, columns))
  new_window_height = whole(saved.new_height, 1, minimum_rows, math.min(new_window_height, minimum_rows))
  if type(saved.enabled) == "boolean" then
    grid_enabled = saved.enabled
  end
  if type(saved.handles) == "boolean" then
    show_handles = saved.handles
  end
end

local function save_settings()
  local file = io.open(settings_path, "w")
  if not file then
    return
  end
  file:write(string.format(
    "return { columns = %d, rows = %d, new_width = %d, new_height = %d, enabled = %s, handles = %s }\n",
    columns, minimum_rows, new_window_width, new_window_height,
    tostring(grid_enabled), tostring(show_handles)
  ))
  file:close()
end

load_settings()

local function target_id(target)
  local window = target.window
  return window and tostring(window.stable_id) or "target:" .. tostring(target.index)
end

local function workspace_id(ctx)
  for _, target in ipairs(ctx.targets) do
    local window = target.window
    if window and window.workspace then
      return tostring(window.workspace.id)
    end
  end
  return nil
end

local function sync_workspace(ctx)
  local key = workspace_id(ctx)
  if not key then
    return nil
  end

  local state = workspaces[key]
  if not state then
    state = { order = {}, rectangles = {}, rows = minimum_rows }
    workspaces[key] = state
  end

  local targets = {}
  for _, target in ipairs(ctx.targets) do
    targets[target_id(target)] = target
  end

  local order = {}
  local seen = {}
  for _, id in ipairs(state.order) do
    if targets[id] then
      table.insert(order, id)
      seen[id] = true
    end
  end
  -- Keep a dragged window's span while Hyprland briefly floats it.
  for _, target in ipairs(ctx.targets) do
    local id = target_id(target)
    if not seen[id] then
      table.insert(order, id)
    end
    if not state.rectangles[id] then
      state.rectangles[id] = { w = new_window_width, h = new_window_height, new = true }
    end
  end
  state.order = order
  return state, targets
end

local function active_id(ctx, state)
  for _, target in ipairs(ctx.targets) do
    if target.window and target.window.active then
      return target_id(target)
    end
  end
  return state.order[#state.order]
end

local function free(occupied, x, y, w, h, rows)
  if x < 1 or y < 1 or x + w - 1 > columns or y + h - 1 > rows then
    return false
  end
  for row = y, y + h - 1 do
    for col = x, x + w - 1 do
      if occupied[row .. ":" .. col] then
        return false
      end
    end
  end
  return true
end

local function find_position(occupied, rectangle, rows)
  local w, h = rectangle.w, rectangle.h
  if rectangle.x and free(occupied, rectangle.x, rectangle.y, w, h, rows) then
    return rectangle.x, rectangle.y
  end

  local best_x, best_y, best_score
  for y = 1, rows - h + 1 do
    for x = 1, columns - w + 1 do
      if free(occupied, x, y, w, h, rows) then
        local score = rectangle.x and
          (math.abs(x - rectangle.x) + math.abs(y - rectangle.y)) or 0
        if not best_score or score < best_score then
          best_x, best_y, best_score = x, y, score
        end
      end
    end
  end
  return best_x, best_y
end

local function reserve(occupied, rectangle)
  for row = rectangle.y, rectangle.y + rectangle.h - 1 do
    for col = rectangle.x, rectangle.x + rectangle.w - 1 do
      occupied[row .. ":" .. col] = true
    end
  end
end

local function arrange(state)
  local order = {}
  local prioritize = pending_window and state.rectangles[pending_window]
  if prioritize then
    table.insert(order, pending_window)
  end
  for _, id in ipairs(state.order) do
    if not prioritize or id ~= pending_window then
      table.insert(order, id)
    end
  end

  local rows = minimum_rows
  for _, id in ipairs(state.order) do
    local rectangle = state.rectangles[id]
    if rectangle.new then
      rows = math.max(rows, state.rows)
      break
    end
  end
  while true do
    local occupied, result = {}, {}
    local complete = true
    for _, id in ipairs(order) do
      local requested = state.rectangles[id]
      local x, y = find_position(occupied, requested, rows)
      if not x and requested.new then
        -- Do not add rows solely to give a new window 3x3 cells.
        requested.w, requested.h = 1, 1
        x, y = find_position(occupied, requested, rows)
      end
      if not x then
        complete = false
        break
      end
      result[id] = { x = x, y = y, w = requested.w, h = requested.h }
      reserve(occupied, result[id])
    end
    if complete then
      for id, rectangle in pairs(result) do
        state.rectangles[id] = rectangle
      end
      state.rows = rows
      if prioritize then
        pending_window = nil
      end
      return
    end
    -- When the grid is full, add rows so every window remains visible.
    rows = rows + 1
  end
end

local function cell_box(area, rectangle, rows)
  local x1 = area.x + math.floor(area.w * (rectangle.x - 1) / columns)
  local x2 = area.x + math.floor(area.w * (rectangle.x + rectangle.w - 1) / columns)
  local y1 = area.y + math.floor(area.h * (rectangle.y - 1) / rows)
  local y2 = area.y + math.floor(area.h * (rectangle.y + rectangle.h - 1) / rows)
  return { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
end

-- Layout messages emit no Hyprland event, so rewrite a file the shell's resize
-- handles and Grid panel watch whenever tiles or settings may have changed.
local layout_signal = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/cellgrid-layout-changed"
local layout_generation = 0

local function signal_layout_change()
  layout_generation = layout_generation + 1
  local file = io.open(layout_signal, "w")
  if file then
    file:write(string.format('{"generation":%d,"enabled":%s,"handles":%s}\n',
      layout_generation, tostring(grid_enabled), tostring(show_handles)))
    file:close()
  end
end

signal_layout_change()

hl.layout.register("cellgrid", {
  recalculate = function(ctx)
    if #ctx.targets == 0 then
      return
    end
    local state, targets = sync_workspace(ctx)
    state.area = ctx.area
    arrange(state)
    for _, id in ipairs(state.order) do
      targets[id]:place(cell_box(ctx.area, state.rectangles[id], state.rows))
    end
  end,

  layout_msg = function(ctx, message)
    local state = sync_workspace(ctx)
    if not state then
      return false
    end
    if message == "refresh" then
      signal_layout_change()
      return true
    end
    if message == "tidy" then
      -- Forget positions so every window packs from the top-left, in order.
      for _, rectangle in pairs(state.rectangles) do
        rectangle.x, rectangle.y = nil, nil
      end
      pending_window = nil
      signal_layout_change()
      return true
    end
    local id = active_id(ctx, state)
    local rectangle = id and state.rectangles[id]
    if not rectangle then
      return false
    end
    rectangle.x = rectangle.x or 1
    rectangle.y = rectangle.y or 1

    if message == "move-left" then
      rectangle.x = clamp(rectangle.x - 1, 1, columns - rectangle.w + 1)
    elseif message == "move-right" then
      rectangle.x = clamp(rectangle.x + 1, 1, columns - rectangle.w + 1)
    elseif message == "move-up" then
      rectangle.y = clamp(rectangle.y - 1, 1, state.rows - rectangle.h + 1)
    elseif message == "move-down" then
      rectangle.y = clamp(rectangle.y + 1, 1, state.rows - rectangle.h + 1)
    elseif message == "grow-width" then
      rectangle.w = clamp(rectangle.w + 1, 1, columns)
      rectangle.x = math.min(rectangle.x, columns - rectangle.w + 1)
    elseif message == "shrink-width" then
      rectangle.w = clamp(rectangle.w - 1, 1, columns)
    elseif message == "grow-height" then
      rectangle.h = clamp(rectangle.h + 1, 1, minimum_rows)
      rectangle.y = math.min(rectangle.y, state.rows - rectangle.h + 1)
    elseif message == "shrink-height" then
      rectangle.h = clamp(rectangle.h - 1, 1, minimum_rows)
    else
      local w, h = message:match("^size%-(%d+)x(%d+)$")
      if not w then
        return "cellgrid: unknown command " .. message
      end
      rectangle.w = clamp(tonumber(w), 1, columns)
      rectangle.h = clamp(tonumber(h), 1, minimum_rows)
      rectangle.x = math.min(rectangle.x, columns - rectangle.w + 1)
      rectangle.y = math.min(rectangle.y, state.rows - rectangle.h + 1)
    end
    pending_window = id
    signal_layout_change()
    return true
  end,
})

-- Pick the grid lines that best match both ends of an axis. The endpoints
-- always span at least one cell, so all four corners land on grid lines.
local function nearest_span(first, last, origin, length, cells)
  local best_start, best_finish, best_error
  for start = 0, cells - 1 do
    local snapped_first = origin + math.floor(length * start / cells)
    for finish = start + 1, cells do
      local snapped_last = origin + math.floor(length * finish / cells)
      local error = (snapped_first - first) ^ 2 + (snapped_last - last) ^ 2
      if not best_error or error < best_error then
        best_start, best_finish, best_error = start, finish, error
      end
    end
  end
  return best_start + 1, best_finish - best_start
end

local function place_at_cursor()
  local window = hl.get_active_window()
  local cursor = hl.get_cursor_pos()
  if not window or window.floating or not window.workspace or not cursor then
    return
  end
  if window.workspace.tiled_layout ~= "lua:cellgrid" then
    return
  end

  local state = workspaces[tostring(window.workspace.id)]
  local id = tostring(window.stable_id)
  local rectangle = state and state.rectangles[id]
  local area = state and state.area
  if not rectangle or not area or area.w <= 0 or area.h <= 0 then
    return
  end

  local box = cell_box(area, rectangle, state.rows)
  -- Hyprland centers a dragged tiled window on the pointer. Reconstruct its
  -- drop rectangle from the pointer, since its reported position may already
  -- have returned to the old tile when the release binding runs.
  local left, top = cursor.x - box.w / 2, cursor.y - box.h / 2
  local x, w = nearest_span(left, left + box.w, area.x, area.w, columns)
  local y, h = nearest_span(top, top + box.h, area.y, area.h, state.rows)

  -- Preserve the old cursor placement when a corner grab otherwise snaps
  -- straight back to the starting tile.
  local cursor_col = math.floor((cursor.x - area.x) * columns / area.w) + 1
  local cursor_row = math.floor((cursor.y - area.y) * state.rows / area.h) + 1
  if x == rectangle.x and y == rectangle.y then
    if cursor_col ~= x then
      x = clamp(cursor_col, 1, columns - w + 1)
    end
    if cursor_row ~= y then
      y = clamp(cursor_row, 1, state.rows - h + 1)
    end
  end
  rectangle.x, rectangle.y, rectangle.w, rectangle.h = x, y, w, h
  pending_window = id
  hl.dispatch(hl.dsp.layout("refresh"))
end

-- The shell's corner resize handles call these through `hyprctl repl` and
-- `hyprctl eval`, addressing windows as Hyprland reports them ("0x...").
local function find_tile(address)
  local window = hl.get_window("address:" .. address)
  if not window or window.floating or not window.workspace
      or window.workspace.tiled_layout ~= "lua:cellgrid" then
    return nil
  end
  local state = workspaces[tostring(window.workspace.id)]
  local id = tostring(window.stable_id)
  local rectangle = state and state.rectangles[id]
  if not rectangle or not rectangle.x or not state.area then
    return nil
  end
  return window, state, id, rectangle
end

local function grid_info(address)
  local _, state, _, rectangle = find_tile(address)
  if not state then
    return ""
  end
  local area = state.area
  return string.format(
    '{"x":%d,"y":%d,"w":%d,"h":%d,"columns":%d,"rows":%d,"max_h":%d,'
      .. '"area":{"x":%d,"y":%d,"w":%d,"h":%d}}',
    rectangle.x, rectangle.y, rectangle.w, rectangle.h, columns, state.rows, minimum_rows,
    math.floor(area.x), math.floor(area.y), math.floor(area.w), math.floor(area.h)
  )
end

local function resize(address, w, h)
  local window, state, id, rectangle = find_tile(address)
  if not rectangle then
    return false
  end
  rectangle.w = clamp(math.floor(w), 1, columns)
  rectangle.h = clamp(math.floor(h), 1, minimum_rows)
  rectangle.x = math.min(rectangle.x, columns - rectangle.w + 1)
  rectangle.y = math.min(rectangle.y, state.rows - rectangle.h + 1)
  pending_window = id
  -- Layout messages go to the focused workspace, so focus the window first.
  hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
  hl.dispatch(hl.dsp.layout("refresh"))
  return true
end

-- The bar's Grid panel reads state through `hyprctl repl` and changes it
-- through `hyprctl eval`.
local function json_string(text)
  return '"' .. tostring(text):gsub('[%c"\\]', function(char)
    if char == '"' or char == "\\" then
      return "\\" .. char
    end
    return string.format("\\u%04x", char:byte())
  end) .. '"'
end

local function settings_json()
  local focused = "null"
  local window = hl.get_active_window()
  if grid_enabled and window then
    local _, _, _, rectangle = find_tile(window.address)
    if rectangle then
      focused = string.format('{"class":%s,"title":%s,"w":%d,"h":%d}',
        json_string(window.class), json_string(window.title), rectangle.w, rectangle.h)
    end
  end
  return string.format(
    '{"enabled":%s,"handles":%s,"columns":%d,"rows":%d,"new_width":%d,"new_height":%d,'
      .. '"limit":%d,"focused":%s}',
    tostring(grid_enabled), tostring(show_handles), columns, minimum_rows,
    new_window_width, new_window_height, grid_limit, focused
  )
end

-- Fit every remembered tile into the current grid. A tile wider than the grid
-- could never be placed, and arrange() would keep adding rows forever.
local function fit_tiles()
  new_window_width = math.min(new_window_width, columns)
  new_window_height = math.min(new_window_height, minimum_rows)
  for _, state in pairs(workspaces) do
    for _, rectangle in pairs(state.rectangles) do
      rectangle.w = math.min(rectangle.w, columns)
      rectangle.h = math.min(rectangle.h, minimum_rows)
      if rectangle.x then
        rectangle.x = math.min(rectangle.x, columns - rectangle.w + 1)
      end
    end
  end
end

local function apply_layout()
  hl.config({ general = { layout = grid_enabled and "lua:cellgrid" or fallback_layout } })
end

local function set_setting(key, value)
  if key == "enabled" or key == "handles" then
    if type(value) ~= "boolean" then
      return false
    end
    if key == "enabled" then
      grid_enabled = value
      apply_layout()
    else
      show_handles = value
    end
  else
    if type(value) ~= "number" then
      return false
    end
    value = math.floor(value)
    if key == "columns" then
      columns = clamp(value, 2, grid_limit)
    elseif key == "rows" then
      minimum_rows = clamp(value, 2, grid_limit)
    elseif key == "new_width" then
      new_window_width = clamp(value, 1, columns)
    elseif key == "new_height" then
      new_window_height = clamp(value, 1, minimum_rows)
    else
      return false
    end
    fit_tiles()
    if grid_enabled then
      hl.dispatch(hl.dsp.layout("refresh"))
    end
  end
  save_settings()
  signal_layout_change()
  return true
end

local function size_focused(w, h)
  if grid_enabled then
    hl.dispatch(hl.dsp.layout(string.format("size-%dx%d",
      clamp(math.floor(w), 1, columns), clamp(math.floor(h), 1, minimum_rows))))
  end
end

local function tidy()
  if grid_enabled then
    hl.dispatch(hl.dsp.layout("tidy"))
  end
end

apply_layout()
hl.layer_rule({ match = { namespace = "cellgrid-resize-handle" }, no_anim = true, animation = "none" })

-- Grid keys do nothing while the panel has switched the grid off.
local function grid_message(message)
  return function()
    if grid_enabled then
      hl.dispatch(hl.dsp.layout(type(message) == "function" and message() or message))
    end
  end
end

-- Resize the focused grid window directly, without entering a submap.
-- SUPER + CTRL keeps these out of apps' Shift/Ctrl + arrow text shortcuts and
-- pairs them with SUPER + CTRL + G; it replaces Omarchy's grouped-window focus.
hl.unbind("SUPER + CTRL + LEFT")
hl.unbind("SUPER + CTRL + RIGHT")
o.bind("SUPER + CTRL + LEFT", "Grid: shrink width", grid_message("shrink-width"), { repeating = true })
o.bind("SUPER + CTRL + RIGHT", "Grid: grow width", grid_message("grow-width"), { repeating = true })
o.bind("SUPER + CTRL + UP", "Grid: shrink height", grid_message("shrink-height"), { repeating = true })
o.bind("SUPER + CTRL + DOWN", "Grid: grow height", grid_message("grow-height"), { repeating = true })

local drag_sequence = os.time() * 1000000
local active_drag_token = nil

local function preview_call(method, payload)
  hl.dispatch(hl.dsp.exec_cmd(
    "omarchy-shell -q shell call matrix.grid " .. method .. " '" .. payload .. "'"
  ))
end

local function drag_with_grid()
  if active_drag_token then
    preview_call("close", tostring(active_drag_token))
    active_drag_token = nil
  end

  local window = hl.get_active_window()
  local state = window and window.workspace and workspaces[tostring(window.workspace.id)]
  local area = state and state.area

  if window and not window.floating and window.workspace.tiled_layout == "lua:cellgrid"
      and area then
    drag_sequence = drag_sequence + 1
    active_drag_token = drag_sequence

    -- Show the grid before Hyprland enters its mouse drag dispatcher.
    local payload = string.format(
      '{"token":%d,"x":%d,"y":%d,"w":%d,"h":%d,"columns":%d,"rows":%d}',
      active_drag_token, area.x, area.y, area.w, area.h, columns, state.rows
    )
    preview_call("open", payload)
  end

  -- Keep the normal Hyprland window drag even when the window is floating.
  hl.dispatch(hl.dsp.window.drag())
end

local function finish_drag()
  if not active_drag_token then
    return
  end
  local token = active_drag_token
  active_drag_token = nil
  preview_call("close", tostring(token))
  place_at_cursor()
end

-- Replace Omarchy's "Move window" binding with the same drag plus its grid guide.
hl.unbind("SUPER + mouse:272")
o.bind("SUPER + mouse:272", "Move window with grid", drag_with_grid, { mouse = true })
o.bind("SUPER + mouse:272", "Place window on grid", finish_drag, { mouse = true, release = true })
-- Also catch mouse release if SUPER was released first; pass ordinary clicks through.
hl.bind("mouse:272", finish_drag, { release = true, ignore_mods = true, non_consuming = true })

-- Enter a temporary key map with SUPER + CTRL + G; Escape leaves it.
o.bind("SUPER + CTRL + G", "Grid controls", hl.dsp.submap("cellgrid"))
hl.define_submap("cellgrid", function()
  hl.bind("ESCAPE", hl.dsp.submap("reset"))
  hl.bind("SUPER + CTRL + G", hl.dsp.submap("reset"))
  hl.bind("LEFT", grid_message("move-left"), { repeating = true })
  hl.bind("RIGHT", grid_message("move-right"), { repeating = true })
  hl.bind("UP", grid_message("move-up"), { repeating = true })
  hl.bind("DOWN", grid_message("move-down"), { repeating = true })
  hl.bind("SHIFT + LEFT", grid_message("shrink-width"), { repeating = true })
  hl.bind("SHIFT + RIGHT", grid_message("grow-width"), { repeating = true })
  hl.bind("SHIFT + UP", grid_message("shrink-height"), { repeating = true })
  hl.bind("SHIFT + DOWN", grid_message("grow-height"), { repeating = true })
  hl.bind("1", grid_message("size-1x1"))
  hl.bind("2", grid_message("size-2x1"))
  hl.bind("3", grid_message("size-2x2"))
  hl.bind("4", grid_message(function()
    return string.format("size-%dx%d", columns, minimum_rows)
  end))
end)

return {
  place_at_cursor = place_at_cursor,
  grid_info = grid_info,
  resize = resize,
  settings_json = settings_json,
  set_setting = set_setting,
  size_focused = size_focused,
  tidy = tidy,
}
