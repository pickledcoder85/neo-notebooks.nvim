local cells = require("neo_notebooks.cells")
local output = require("neo_notebooks.output")
local config = require("neo_notebooks").config
local containment = require("neo_notebooks.containment")
local policy = require("neo_notebooks.policy")

local M = {}

local function contained_open_line_below_keys(bufnr)
  return string.format("<C-o><Cmd>lua require('neo_notebooks.actions').open_line_below(%d)<CR>", bufnr)
end

local function decision_keys(bufnr, decision)
  if decision.action == "block" then
    if decision.reason and decision.reason ~= "" then
      vim.notify(decision.reason, vim.log.levels.WARN)
    end
    return ""
  end
  if decision.action == "redirect" then
    if decision.target == "open_line_below" then
      return contained_open_line_below_keys(bufnr)
    end
    return ""
  end
  return decision.keys or ""
end

local function mark_pending_virtual_indent(bufnr, line, pad)
  local pending = vim.b[bufnr].neo_notebooks_pending_virtual_indent or {}
  pending[tostring(line)] = pad
  vim.b[bufnr].neo_notebooks_pending_virtual_indent = pending
end

function M.get_cursor_state(bufnr, line, col)
  bufnr = bufnr or 0
  return containment.cursor_state(bufnr, line, col)
end

function M.cell_has_nonempty_body(bufnr, line)
  bufnr = bufnr or 0
  line = line or (vim.api.nvim_win_get_cursor(0)[1] - 1)
  local cell = containment.get_cell(bufnr, line)
  if not cell then
    return false
  end
  local body = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
  for _, body_line in ipairs(body) do
    if body_line:match("%S") then
      return true
    end
  end
  return false
end

local function left_boundary_col(cell)
  if cell.layout and cell.layout.left_col then
    return cell.layout.left_col + 1
  end
  local win_width = vim.api.nvim_win_get_width(0)
  local ratio = config.cell_width_ratio or 0.9
  local width = math.floor(win_width * ratio)
  width = math.max(config.cell_min_width or 60, width)
  width = math.min(config.cell_max_width or win_width, width)
  width = math.min(width, win_width)
  width = math.max(10, width)
  local pad = math.max(0, math.floor((win_width - width) / 2))
  return pad + 1
end

function M.duplicate_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1

  local cell = cells.get_cell_at_line(bufnr, line)
  if cell.id then
    local index = require("neo_notebooks.index")
    local entry = index.get_by_id(bufnr, cell.id)
    if entry then
      cell.start = entry.start
      cell.finish = entry.finish
    end
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.finish + 1, false)
  local insert_at = cell.finish + 1

  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, lines)
  local index = require("neo_notebooks.index")
  index.mark_dirty(bufnr)
  local new_start = insert_at
  vim.api.nvim_win_set_cursor(0, { new_start + 2, 0 })
  M.clamp_cursor_to_cell_left(bufnr, { force = true, clamp_to_line = true })
end

function M.split_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1

  local cell = cells.get_cell_at_line(bufnr, line)
  if cell.id then
    local index = require("neo_notebooks.index")
    local entry = index.get_by_id(bufnr, cell.id)
    if entry then
      cell.start = entry.start
      cell.finish = entry.finish
    end
  end
  if line <= cell.start then
    vim.notify("Place cursor inside the cell body to split", vim.log.levels.WARN)
    return
  end

  local marker = "# %% [" .. cell.type .. "]"
  vim.api.nvim_buf_set_lines(bufnr, line, line, false, { marker })
  if cell.id then
    output.clear_by_id(bufnr, cell.id)
  end
  local index = require("neo_notebooks.index")
  index.mark_dirty(bufnr)
  vim.api.nvim_win_set_cursor(0, { line + 2, 0 })
  vim.cmd("startinsert")
end

function M.clear_output(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if cell.id then
    local index = require("neo_notebooks.index")
    local entry = index.get_by_id(bufnr, cell.id)
    if entry then
      cell.start = entry.start
    end
  end
  output.clear_cell(bufnr, cell.start)
end

function M.clear_all_output(bufnr)
  bufnr = bufnr or 0
  output.clear_all(bufnr)
end

function M.delete_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if cell.id then
    local index = require("neo_notebooks.index")
    local entry = index.get_by_id(bufnr, cell.id)
    if entry then
      cell.start = entry.start
      cell.finish = entry.finish
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, cell.start, cell.finish + 1, false, {})
  local index = require("neo_notebooks.index")
  index.mark_dirty(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local target = math.max(1, cell.start + 1)
  target = math.min(target, math.max(1, line_count))
  vim.api.nvim_win_set_cursor(0, { target, 0 })
  local next_cell = cells.get_cell_at_line(bufnr, math.max(0, target - 1))
  if next_cell then
    local body_line = math.min(next_cell.start + 1, next_cell.finish)
    vim.api.nvim_win_set_cursor(0, { body_line + 1, 0 })
  end
  M.clamp_cursor_to_cell_left(bufnr, { force = true, clamp_to_line = true })
end

function M.yank_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if cell.id then
    local index = require("neo_notebooks.index")
    local entry = index.get_by_id(bufnr, cell.id)
    if entry then
      cell.start = entry.start
      cell.finish = entry.finish
    end
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.finish + 1, false)
  vim.fn.setreg("\"", lines)
  vim.notify("NeoNotebook: cell yanked", vim.log.levels.INFO)
end

local function move_once(bufnr, direction)
  local index = require("neo_notebooks.index")
  local state = index.get(bufnr)
  local list = state.list
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local idx = nil
  for i, cell in ipairs(list) do
    if line >= cell.start and line <= cell.finish then
      idx = i
      break
    end
  end
  if not idx then
    return
  end

  if direction < 0 and idx == 1 then
    return
  end
  if direction > 0 and idx == #list then
    return
  end

  local current = list[idx]
  local swap = list[idx + direction]
  local id = current.id
  local cell_type = current.type
  local swap_id = swap.id
  local swap_type = swap.type
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, current.start, current.finish + 1, false)
  local current_len = current.finish - current.start + 1

  vim.api.nvim_buf_set_lines(bufnr, current.start, current.finish + 1, false, {})
  local insert_at = direction < 0 and swap.start or (swap.finish - current_len + 1)
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, current_lines)
  if id then
    vim.api.nvim_buf_set_extmark(bufnr, index.ns, insert_at, 0, { id = id })
  end
  local max_line = vim.api.nvim_buf_line_count(bufnr)
  local target = math.min(insert_at + 2, max_line)
  vim.api.nvim_win_set_cursor(0, { target, 0 })
  index.mark_dirty(bufnr)
end

function M.move_cell_up(bufnr, line, count)
  bufnr = bufnr or 0
  count = count or vim.v.count1
  for _ = 1, count do
    move_once(bufnr, -1)
  end
end

function M.move_cell_down(bufnr, line, count)
  bufnr = bufnr or 0
  count = count or vim.v.count1
  for _ = 1, count do
    move_once(bufnr, 1)
  end
end

function M.move_cell_top(bufnr)
  bufnr = bufnr or 0
  local index = require("neo_notebooks.index")
  local state = index.get(bufnr)
  local list = state.list
  if #list == 0 then
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local idx = nil
  for i, cell in ipairs(list) do
    if line >= cell.start and line <= cell.finish then
      idx = i
      break
    end
  end
  if not idx or idx == 1 then
    return
  end
  local current = list[idx]
  local id = current.id
  local cell_type = current.type
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, current.start, current.finish + 1, false)
  vim.api.nvim_buf_set_lines(bufnr, current.start, current.finish + 1, false, {})
  local insert_at = list[1].start
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, current_lines)
  if id then
    vim.api.nvim_buf_set_extmark(bufnr, index.ns, insert_at, 0, { id = id })
  end
  vim.api.nvim_win_set_cursor(0, { insert_at + 2, 0 })
  index.mark_dirty(bufnr)
end

function M.move_cell_bottom(bufnr)
  bufnr = bufnr or 0
  local index = require("neo_notebooks.index")
  local state = index.get(bufnr)
  local list = state.list
  if #list == 0 then
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local idx = nil
  for i, cell in ipairs(list) do
    if line >= cell.start and line <= cell.finish then
      idx = i
      break
    end
  end
  if not idx or idx == #list then
    return
  end
  local current = list[idx]
  local id = current.id
  local cell_type = current.type
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, current.start, current.finish + 1, false)
  vim.api.nvim_buf_set_lines(bufnr, current.start, current.finish + 1, false, {})
  local insert_at = list[#list].finish + 1
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, current_lines)
  if id then
    vim.api.nvim_buf_set_extmark(bufnr, index.ns, insert_at, 0, { id = id })
  end
  vim.api.nvim_win_set_cursor(0, { insert_at + 2, 0 })
  index.mark_dirty(bufnr)
end

function M.toggle_output_mode()
  local nb = require("neo_notebooks")
  if nb.config.output == "inline" then
    nb.config.output = "float"
    vim.notify("NeoNotebook: output mode = float", vim.log.levels.INFO)
  else
    nb.config.output = "inline"
    vim.notify("NeoNotebook: output mode = inline", vim.log.levels.INFO)
  end
end

function M.select_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  local start = math.min(cell.finish, cell.start + 1)
  local finish = math.max(start, cell.finish)
  vim.api.nvim_win_set_cursor(0, { start + 1, 0 })
  vim.cmd("normal! V")
  vim.api.nvim_win_set_cursor(0, { finish + 1, 0 })
end

function M.toggle_auto_render()
  local nb = require("neo_notebooks")
  nb.config.auto_render = not nb.config.auto_render
  vim.notify(string.format("NeoNotebook: auto_render = %s", tostring(nb.config.auto_render)), vim.log.levels.INFO)
end

function M.toggle_cell_index()
  local nb = require("neo_notebooks")
  nb.config.show_cell_index = not nb.config.show_cell_index
  vim.notify(string.format("NeoNotebook: show_cell_index = %s", tostring(nb.config.show_cell_index)), vim.log.levels.INFO)
end

function M.open_line_below(bufnr)
  bufnr = bufnr or 0
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = containment.get_cell(bufnr, line)
  cell = containment.ensure_body_line(bufnr, cell)
  local insert_at = containment.clamped_insert_at(cell, line + 1)
  -- If containment clamping would place insertion at/above cursor on bottom lines,
  -- force a true "below" insert so Enter grows the active cell downward.
  if insert_at <= line then
    insert_at = math.min(line + 1, cell.finish + 1)
  end
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { "" })
  local index = require("neo_notebooks.index")
  index.on_text_changed(bufnr)
  local target_col = left_boundary_col(cell)
  vim.api.nvim_set_option_value("virtualedit", "all", { win = 0 })
  vim.api.nvim_win_set_cursor(0, { insert_at + 1, 0 })
  vim.cmd("normal! " .. tostring(target_col + 1) .. "|")
  mark_pending_virtual_indent(bufnr, insert_at, target_col)
  vim.cmd("startinsert")
end

function M.open_line_above(bufnr)
  bufnr = bufnr or 0
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = containment.get_cell(bufnr, line)
  cell = containment.ensure_body_line(bufnr, cell)
  local insert_at = containment.clamped_insert_at(cell, line)
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { "" })
  local index = require("neo_notebooks.index")
  index.on_text_changed(bufnr)
  local target_col = left_boundary_col(cell)
  vim.api.nvim_set_option_value("virtualedit", "all", { win = 0 })
  vim.api.nvim_win_set_cursor(0, { insert_at + 1, 0 })
  vim.cmd("normal! " .. tostring(target_col + 1) .. "|")
  mark_pending_virtual_indent(bufnr, insert_at, target_col)
  vim.cmd("startinsert")
end

function M.insert_newline_in_cell(bufnr)
  bufnr = bufnr or 0
  local decision = policy.decide(bufnr, "insert_cr")
  return decision_keys(bufnr, decision)
end

function M.handle_enter_insert(bufnr)
  bufnr = bufnr or 0
  local decision = policy.decide(bufnr, "insert_cr")
  if decision.action == "block" then
    if decision.reason and decision.reason ~= "" then
      vim.notify(decision.reason, vim.log.levels.WARN)
    end
    return
  end
  if decision.action == "redirect" and decision.target == "open_line_below" then
    M.open_line_below(bufnr)
    return
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", true)
  vim.schedule(function()
    if not vim.api.nvim_get_mode().mode:match("^i") then
      return
    end
    local state = containment.cursor_state(bufnr)
    if not state.cell then
      return
    end
    local target_col = left_boundary_col(state.cell)
    vim.api.nvim_set_option_value("virtualedit", "all", { win = 0 })
    vim.cmd("normal! " .. tostring(target_col + 1) .. "|")
    mark_pending_virtual_indent(bufnr, state.line, target_col)
  end)
end

function M.handle_enter_normal(bufnr)
  bufnr = bufnr or 0
  local state = containment.cursor_state(bufnr)
  if not state.cell then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", true)
    return
  end
  local cell = state.cell
  cell = containment.ensure_body_line(bufnr, cell)
  state = containment.cursor_state(bufnr)
  local target = state.line + 1
  if target < state.body_start then
    target = state.body_start
  end
  if state.has_next then
    target = math.min(target, state.protected_floor)
  else
    target = math.min(target, math.max(state.body_start, state.cell.finish))
  end
  target = math.max(state.body_start, target)
  local col = left_boundary_col(state.cell)
  vim.api.nvim_win_set_cursor(0, { target + 1, col })
end

function M.guard_backspace_in_insert(bufnr)
  bufnr = bufnr or 0
  local decision = policy.decide(bufnr, "insert_bs")
  return decision_keys(bufnr, decision)
end

function M.guard_delete_in_insert(bufnr)
  bufnr = bufnr or 0
  local decision = policy.decide(bufnr, "insert_del")
  return decision_keys(bufnr, decision)
end

function M.clamp_cursor_to_cell_left(bufnr, opts)
  bufnr = bufnr or 0
  opts = opts or {}
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local col = cursor[2]
  local cell = containment.get_cell(bufnr, line)
  if not cell then
    return
  end
  cell = containment.ensure_body_line(bufnr, cell)
  local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
  if text ~= "" and not opts.force then
    return
  end
  local target_col = left_boundary_col(cell)
  if opts.force or col < target_col then
    if opts.clamp_to_line then
      local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
      local line_len = #text
      local final_col = target_col
      if line_len == 0 then
        final_col = target_col
      else
        final_col = math.min(target_col, line_len - 1)
      end
      vim.api.nvim_win_set_cursor(0, { line + 1, final_col })
    else
      vim.api.nvim_set_option_value("virtualedit", "all", { win = 0 })
      vim.api.nvim_win_set_cursor(0, { line + 1, 0 })
      vim.cmd("normal! " .. tostring(target_col + 1) .. "|")
    end
  end
end

function M.contain_insert_entry(bufnr)
  bufnr = bufnr or 0
  local state = containment.cursor_state(bufnr)
  if not state.cell then
    return
  end
  local cell = containment.ensure_body_line(bufnr, state.cell)
  state = containment.cursor_state(bufnr)

  local target = state.line
  if state.line <= cell.start then
    target = state.body_start
  elseif state.has_next and state.line >= state.protected_floor then
    target = math.max(state.body_start, state.protected_floor - 1)
  end

  local target_col = left_boundary_col(cell)
  if target ~= state.line or state.col < target_col then
    vim.api.nvim_set_option_value("virtualedit", "all", { win = 0 })
    vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
    vim.cmd("normal! " .. tostring(target_col + 1) .. "|")
  end
end

function M.consume_pending_virtual_indent(bufnr)
  bufnr = bufnr or 0
  local pending = vim.b[bufnr].neo_notebooks_pending_virtual_indent
  if not pending then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1] - 1
  local key = tostring(line)
  local pad = pending[key]
  if not pad or pad <= 0 then
    return
  end
  local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
  if text == "" then
    return
  end
  if not text:match("%S") then
    return
  end
  local leading = #(text:match("^(%s*)") or "")
  local trim = math.min(leading, pad)
  if trim > 0 then
    local new_text = text:sub(trim + 1)
    vim.api.nvim_buf_set_lines(bufnr, line, line + 1, false, { new_text })
    local col = math.max(0, cursor[2] - trim)
    vim.api.nvim_win_set_cursor(0, { line + 1, col })
  end
  pending[key] = nil
  vim.b[bufnr].neo_notebooks_pending_virtual_indent = pending
end

function M.normalize_spacing(bufnr)
  bufnr = bufnr or 0
  if not config.trim_cell_spacing then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local markers = {}
  for i, line in ipairs(lines) do
    if containment.marker_type(line) then
      table.insert(markers, i)
    end
  end
  if #markers <= 1 then
    return
  end

  local remove = {}
  local keep = math.max(0, config.cell_gap_lines or 0)
  for i = 1, #markers - 1 do
    local start_marker = markers[i]
    local next_marker = markers[i + 1]
    local last_nonempty = start_marker
    for j = next_marker - 1, start_marker + 1, -1 do
      if lines[j] ~= "" then
        last_nonempty = j
        break
      end
    end
    local gap_start = last_nonempty + 1 + keep
    local gap_end = next_marker - 1
    if gap_start <= gap_end then
      table.insert(remove, { start = gap_start - 1, stop = gap_end })
    end
  end
  if #remove == 0 then
    return
  end

  for i = #remove, 1, -1 do
    local r = remove[i]
    vim.api.nvim_buf_set_lines(bufnr, r.start, r.stop, false, {})
  end
end

function M.guard_delete_current_line(bufnr, count)
  bufnr = bufnr or 0
  local decision = policy.decide(bufnr, "delete_line", { count = count })
  return decision_keys(bufnr, decision)
end

function M.guard_delete_char(bufnr)
  bufnr = bufnr or 0
  local decision = policy.decide(bufnr, "delete_char")
  return decision_keys(bufnr, decision)
end

function M.guard_delete_to_eol(bufnr)
  bufnr = bufnr or 0
  local decision = policy.decide(bufnr, "delete_to_eol")
  return decision_keys(bufnr, decision)
end

function M.guard_visual_delete(bufnr, mode_override, first_line, last_line)
  bufnr = bufnr or 0
  local decision = policy.decide(bufnr, "delete_visual", {
    mode = mode_override,
    first_line = first_line,
    last_line = last_line,
  })
  return decision_keys(bufnr, decision)
end

function M.handle_paste_below(bufnr)
  bufnr = bufnr or 0
  local state = containment.cursor_state(bufnr)
  if not state.cell then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("p", true, false, true), "n", true)
    return
  end
  if state.has_next and state.line >= state.protected_floor then
    local cell = containment.ensure_body_line(bufnr, state.cell)
    local insert_at = math.min(state.line + 1, cell.finish + 1)
    vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { "" })
    local index = require("neo_notebooks.index")
    index.on_text_changed(bufnr)
    vim.api.nvim_win_set_cursor(0, { insert_at, 0 })
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("p", true, false, true), "n", true)
end

function M.goto_cell_top(bufnr)
  bufnr = bufnr or 0
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = containment.get_cell(bufnr, line)
  cell = containment.ensure_body_line(bufnr, cell)
  local target = cell.start + 1
  local col = left_boundary_col(cell)
  vim.api.nvim_win_set_cursor(0, { target + 1, col })
end

function M.goto_cell_bottom(bufnr)
  bufnr = bufnr or 0
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = containment.get_cell(bufnr, line)
  cell = containment.ensure_body_line(bufnr, cell)
  local target = cell.finish
  if containment.has_next_marker(bufnr, cell) then
    local keep = math.max(0, config.cell_gap_lines or 0)
    target = math.max(cell.start + 1, cell.finish - keep)
  else
    target = math.max(cell.start + 1, cell.finish)
  end
  local col = left_boundary_col(cell)
  vim.api.nvim_win_set_cursor(0, { target + 1, col })
end

local function cell_editable_bottom(bufnr, cell)
  local keep = 0
  if containment.has_next_marker(bufnr, cell) then
    keep = math.max(0, config.cell_gap_lines or 0)
  end
  return math.max(cell.start + 1, cell.finish - keep)
end

function M.move_line_down_contained(bufnr, count)
  bufnr = bufnr or 0
  count = count or vim.v.count1
  for _ = 1, count do
    local state = containment.cursor_state(bufnr)
    if not state.cell then
      vim.cmd("normal! j")
      return
    end
    local target = state.line + 1
    local bottom = cell_editable_bottom(bufnr, state.cell)
    target = math.min(target, bottom)
    target = math.max(state.body_start, target)
    local left_col = left_boundary_col(state.cell)
    local text = vim.api.nvim_buf_get_lines(bufnr, target, target + 1, false)[1] or ""
    local line_len = #text
    local col = math.max(state.col, left_col)
    if line_len == 0 then
      col = left_col
    else
      col = math.min(col, line_len - 1)
    end
    vim.api.nvim_win_set_cursor(0, { target + 1, col })
  end
end

function M.move_line_up_contained(bufnr, count)
  bufnr = bufnr or 0
  count = count or vim.v.count1
  for _ = 1, count do
    local state = containment.cursor_state(bufnr)
    if not state.cell then
      vim.cmd("normal! k")
      return
    end
    local target = state.line - 1
    target = math.max(state.body_start, target)
    local left_col = left_boundary_col(state.cell)
    local text = vim.api.nvim_buf_get_lines(bufnr, target, target + 1, false)[1] or ""
    local line_len = #text
    local col = math.max(state.col, left_col)
    if line_len == 0 then
      col = left_col
    else
      col = math.min(col, line_len - 1)
    end
    vim.api.nvim_win_set_cursor(0, { target + 1, col })
  end
end

function M.goto_line_first_nonblank_contained(bufnr)
  bufnr = bufnr or 0
  local state = containment.cursor_state(bufnr)
  if not state.cell then
    vim.cmd("normal! _")
    return
  end
  local line = state.line
  local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
  local first = text:find("%S")
  local left_col = nil
  if state.cell and state.cell.layout and state.cell.layout.left_col then
    left_col = state.cell.layout.left_col
  else
    left_col = left_boundary_col(state.cell) - 1
  end
  local col = left_col
  if first then
    col = left_col + (first - 1)
  end
  vim.api.nvim_win_set_cursor(0, { line + 1, col })
end

function M.fold_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)

  vim.api.nvim_set_option_value("foldmethod", "manual", { win = 0 })
  vim.api.nvim_set_option_value("foldenable", true, { win = 0 })
  vim.cmd(string.format("%d,%dfold", cell.start + 1, cell.finish + 1))
end

function M.unfold_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  vim.cmd(string.format("%d,%dfoldopen", cell.start + 1, cell.finish + 1))
end

function M.toggle_fold_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  local level = vim.fn.foldlevel(cell.start + 1)
  if level > 0 and vim.fn.foldclosed(cell.start + 1) ~= -1 then
    M.unfold_cell(bufnr, line)
  else
    M.fold_cell(bufnr, line)
  end
end

return M
