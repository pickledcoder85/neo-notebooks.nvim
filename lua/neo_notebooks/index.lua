local cells = require("neo_notebooks.cells")

local M = {}
M.ns = vim.api.nvim_create_namespace("neo_notebooks_cell_ids")

local MARKER_PATTERN = "^# %%%% %[(%w+)%]%s*$"

local function current_tick(bufnr)
  return vim.api.nvim_buf_get_changedtick(bufnr)
end

local meta_store = {}

local function get_meta(bufnr)
  local meta = meta_store[bufnr]
  if not meta then
    meta = {}
    meta_store[bufnr] = meta
  end
  if meta.orphans == nil then
    meta.orphans = {}
  end
  if meta.render_hint == nil then
    meta.render_hint = "debounce"
  end
  return meta
end

local function set_state(bufnr, state)
  vim.b[bufnr].neo_notebooks_index = state
  local meta = get_meta(bufnr)
  meta.tick = current_tick(bufnr)
  meta.dirty = false
  meta.marker_dirty = false
end

local function build_index(bufnr, prev_state, orphans)
  bufnr = bufnr or 0
  local list = cells.get_cells(bufnr)
  local index = { list = {}, by_id = {} }
  local used = {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  local function find_or_create_id(line)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, M.ns, { line, 0 }, { line, -1 }, { details = false })
    if #marks > 0 then
      return marks[1][1]
    end
    local chosen = nil
    if orphans and #orphans > 0 then
      local exact_i = nil
      for i, orphan in ipairs(orphans) do
        if orphan.line == line then
          exact_i = i
          break
        end
      end
      if exact_i then
        chosen = table.remove(orphans, exact_i).id
      else
        local best_i = nil
        local best_dist = nil
        for i, orphan in ipairs(orphans) do
          local dist = math.abs(line - orphan.line)
          if best_dist == nil or dist < best_dist then
            best_dist = dist
            best_i = i
          end
        end
        if best_i then
          chosen = table.remove(orphans, best_i).id
        end
      end
    end
    if chosen then
      return vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, { id = chosen })
    end
    return vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {})
  end

  for i, cell in ipairs(list) do
    local line = math.min(cell.start, line_count - 1)
    local id = find_or_create_id(line)
    used[id] = true
    local entry = {
      id = id,
      type = cell.type,
      start = cell.start,
      finish = cell.finish,
      body_len = cell.finish - cell.start + 1,
      border = cell.border ~= false,
    }
    table.insert(index.list, entry)
    index.by_id[entry.id] = entry
  end

  local all = vim.api.nvim_buf_get_extmarks(bufnr, M.ns, 0, -1, {})
  for _, mark in ipairs(all) do
    local id = mark[1]
    if not used[id] then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, id)
    end
  end

  return index
end

local function has_marker_in_range(state, firstline, lastline)
  if not state or not state.list then
    return false
  end
  for _, cell in ipairs(state.list) do
    if cell.border ~= false and cell.start >= firstline and cell.start < lastline then
      return true
    end
  end
  return false
end

local function has_marker_in_new_lines(bufnr, firstline, new_lastline)
  if new_lastline <= firstline then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, firstline, new_lastline, false)
  for _, line in ipairs(lines) do
    if line:match(MARKER_PATTERN) then
      return true
    end
  end
  return false
end

local function clear_layout(cell)
  cell.layout = nil
end

local function apply_delta(state, firstline, lastline, delta)
  if not state or not state.list or delta == 0 then
    return
  end
  for _, cell in ipairs(state.list) do
    if cell.start >= lastline then
      cell.start = cell.start + delta
      cell.finish = cell.finish + delta
      clear_layout(cell)
    elseif cell.finish >= lastline then
      cell.finish = cell.finish + delta
      if cell.finish < cell.start then
        cell.finish = cell.start
      end
      clear_layout(cell)
    end
  end
end

local function find_cell_in_state(state, line)
  if not state or not state.list or #state.list == 0 then
    return nil
  end
  for _, cell in ipairs(state.list) do
    if line >= cell.start and line <= cell.finish then
      return cell
    end
  end
  return state.list[#state.list]
end

local function normalize_cell_type(cell_type)
  if not cell_type or cell_type == "" then
    return "code"
  end
  cell_type = cell_type:lower()
  if cell_type ~= "code" and cell_type ~= "markdown" then
    return "code"
  end
  return cell_type
end

local function mark_dirty_cells_in_range(state, dirty_set, firstline, lastline)
  if not state or not state.list or not dirty_set then
    return
  end
  if lastline <= firstline then
    return
  end
  local range_start = firstline
  local range_end = lastline - 1
  for _, cell in ipairs(state.list) do
    if cell.finish < range_start then
      goto continue
    end
    if cell.start > range_end then
      break
    end
    if cell.id then
      dirty_set[cell.id] = true
    end
    ::continue::
  end
end

local function update_marker_types_in_range(bufnr, state, dirty_set, firstline, lastline)
  if not state or not state.list then
    return false
  end
  local touched = false
  for _, cell in ipairs(state.list) do
    if cell.border ~= false and cell.start >= firstline and cell.start < lastline then
      local line = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.start + 1, false)[1]
      local cell_type = line and line:match(MARKER_PATTERN) or nil
      if not cell_type then
        return false
      end
      cell.type = normalize_cell_type(cell_type)
      if cell.id then
        dirty_set[cell.id] = true
      end
      touched = true
    end
  end
  return touched
end

function M.get(bufnr)
  bufnr = bufnr or 0
  local state = vim.b[bufnr].neo_notebooks_index
  local meta = get_meta(bufnr)
  local stale = (not state) or meta.dirty or (meta.tick ~= current_tick(bufnr))
  if stale then
    state = build_index(bufnr, state, meta.orphans)
    set_state(bufnr, state)
    meta.orphans = {}
  end
  return state
end

function M.rebuild(bufnr)
  bufnr = bufnr or 0
  local meta = get_meta(bufnr)
  local state = build_index(bufnr, vim.b[bufnr].neo_notebooks_index, meta.orphans)
  set_state(bufnr, state)
  meta.orphans = {}
  return state
end

function M.mark_dirty(bufnr)
  bufnr = bufnr or 0
  local meta = get_meta(bufnr)
  meta.dirty = true
  meta.marker_dirty = true
  meta.dirty_cell_ids = nil
end

function M.find_cell(bufnr, line)
  bufnr = bufnr or 0
  local state = M.get(bufnr)
  for _, cell in ipairs(state.list) do
    if line >= cell.start and line <= cell.finish then
      return cell
    end
  end
  return state.list[#state.list]
end

function M.is_attached(bufnr)
  bufnr = bufnr or 0
  return vim.b[bufnr] and vim.b[bufnr].neo_notebooks_index_attached == true
end

function M.attach(bufnr)
  bufnr = bufnr or 0
  if M.is_attached(bufnr) then
    return
  end
  vim.b[bufnr].neo_notebooks_index_attached = true
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, _, _, firstline, lastline, new_lastline)
      M.on_lines(bufnr, firstline, lastline, new_lastline)
    end,
    on_detach = function()
      if vim.b[bufnr] then
        vim.b[bufnr].neo_notebooks_index_attached = false
      end
      meta_store[bufnr] = nil
    end,
  })
end

function M.on_lines(bufnr, firstline, lastline, new_lastline)
  bufnr = bufnr or 0
  local meta = get_meta(bufnr)
  if meta.dirty then
    return
  end
  local state = vim.b[bufnr].neo_notebooks_index
  if not state or not state.list then
    meta.dirty = true
    return
  end
  local marker_in_range = has_marker_in_range(state, firstline, lastline)
  local inserted_markers = has_marker_in_new_lines(bufnr, firstline, new_lastline)
  local marker_touched = marker_in_range or inserted_markers
  if marker_touched then
    local delta = new_lastline - lastline
    if not inserted_markers and delta == 0 then
      meta.dirty_cell_ids = meta.dirty_cell_ids or {}
      local ok = update_marker_types_in_range(bufnr, state, meta.dirty_cell_ids, firstline, lastline)
      if ok then
        vim.b[bufnr].neo_notebooks_index = state
        meta.tick = current_tick(bufnr)
        meta.dirty = false
        meta.marker_dirty = false
        meta.render_hint = "immediate"
        return
      end
    end
    local orphans = meta.orphans or {}
    for _, cell in ipairs(state.list) do
      if cell.border ~= false and cell.start >= firstline and cell.start < lastline then
        local line = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.start + 1, false)[1]
        if not line or not line:match(MARKER_PATTERN) then
          table.insert(orphans, { id = cell.id, line = cell.start, type = cell.type })
        end
      end
    end
    meta.orphans = orphans
    meta.dirty = true
    meta.marker_dirty = true
    meta.dirty_cell_ids = nil
    meta.render_hint = "immediate"
    return
  end
  meta.dirty_cell_ids = meta.dirty_cell_ids or {}
  local range_last = math.max(lastline, new_lastline)
  mark_dirty_cells_in_range(state, meta.dirty_cell_ids, firstline, range_last)
  local delta = new_lastline - lastline
  if delta ~= 0 then
    apply_delta(state, firstline, lastline, delta)
    meta.dirty_cell_ids = meta.dirty_cell_ids or {}
    for _, cell in ipairs(state.list) do
      if cell.start >= lastline then
        meta.dirty_cell_ids[cell.id] = true
      end
    end
    vim.b[bufnr].neo_notebooks_index = state
    meta.tick = current_tick(bufnr)
    meta.dirty = false
    meta.marker_dirty = false
    meta.render_hint = "immediate"
    return
  end
  vim.b[bufnr].neo_notebooks_index = state
  meta.tick = current_tick(bufnr)
  meta.dirty = false
  meta.marker_dirty = false
  meta.render_hint = "debounce"
end

function M.on_text_changed(bufnr)
  bufnr = bufnr or 0
  if not M.is_attached(bufnr) then
    M.mark_dirty(bufnr)
  end
end

function M.consume_dirty_cells(bufnr)
  bufnr = bufnr or 0
  local meta = get_meta(bufnr)
  if meta.dirty or meta.marker_dirty then
    return nil
  end
  local set = meta.dirty_cell_ids
  if not set then
    return nil
  end
  meta.dirty_cell_ids = nil
  local list = {}
  for id in pairs(set) do
    table.insert(list, id)
  end
  if #list == 0 then
    return nil
  end
  return list
end

function M.consume_render_hint(bufnr)
  bufnr = bufnr or 0
  local meta = get_meta(bufnr)
  local hint = meta.render_hint or "debounce"
  meta.render_hint = "debounce"
  return hint
end

function M.get_by_id(bufnr, id)
  bufnr = bufnr or 0
  local state = M.get(bufnr)
  return state.by_id[id]
end

function M.set_layout(bufnr, id, layout)
  bufnr = bufnr or 0
  if not id or not layout then
    return
  end
  local state = M.get(bufnr)
  local cell = state.by_id[id]
  if not cell then
    return
  end
  cell.layout = {
    left_col = layout.left_col,
    right_col = layout.right_col,
    top_line = layout.top_line,
    bottom_line = layout.bottom_line,
  }
end

return M
