local config = require("neo_notebooks").config

local M = {}

function M.marker_type(line)
  if not line then
    return nil
  end
  return line:match("^# %%%% %[(%w+)%]%s*$")
end

function M.get_cell(bufnr, line)
  bufnr = bufnr or 0
  local index = require("neo_notebooks.index")
  local entry = index.find_cell(bufnr, line)
  if not entry then
    return nil
  end
  return {
    id = entry.id,
    type = entry.type,
    start = entry.start,
    finish = entry.finish,
    border = entry.border,
  }
end

function M.has_next_marker(bufnr, cell)
  local marker_line = cell.finish + 1
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if marker_line < 0 or marker_line >= line_count then
    return false
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, marker_line, marker_line + 1, false)[1]
  return M.marker_type(line) ~= nil
end

function M.ensure_body_line(bufnr, cell)
  if cell.finish >= cell.start + 1 then
    return cell
  end
  local insert_at = cell.start + 1
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { "" })
  local index = require("neo_notebooks.index")
  index.rebuild(bufnr)
  return M.get_cell(bufnr, insert_at)
end

function M.clamped_insert_at(cell, candidate)
  local keep = math.max(0, config.cell_gap_lines or 0)
  local next_marker = cell.finish + 1
  local max_inside = next_marker - keep
  local insert_at = candidate
  if keep > 0 then
    insert_at = math.min(insert_at, max_inside)
  end
  insert_at = math.min(insert_at, cell.finish + 1)
  insert_at = math.max(insert_at, cell.start + 1)
  return insert_at
end

function M.cursor_state(bufnr, line_override, col_override)
  bufnr = bufnr or 0
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = line_override
  local col = col_override
  if line == nil then
    line = cursor[1] - 1
  end
  if col == nil then
    col = cursor[2]
  end

  local index_mod = require("neo_notebooks.index")
  local index_state = index_mod.get(bufnr)
  local cell = M.get_cell(bufnr, line)
  local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
  local prev_text = (line > 0 and (vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or "")) or ""

  if not cell then
    return {
      line = line,
      col = col,
      text = text,
      prev_text = prev_text,
      active_cell_id = nil,
      active_cell_index = nil,
      index = index_state,
    }
  end

  local body_start = cell.start + 1
  local keep = 0
  local has_next = M.has_next_marker(bufnr, cell)
  if has_next then
    keep = math.max(0, config.cell_gap_lines or 0)
  end

  local active_cell_index = nil
  if index_state and index_state.list then
    for i, entry in ipairs(index_state.list) do
      if entry.id == cell.id then
        active_cell_index = i
        break
      end
    end
  end

  return {
    cell = cell,
    active_cell_id = cell.id,
    active_cell_index = active_cell_index,
    index = index_state,
    line = line,
    col = col,
    text = text,
    prev_text = prev_text,
    body_start = body_start,
    has_body = cell.finish >= body_start,
    has_next = has_next,
    keep = keep,
    next_marker_line = cell.finish + 1,
    protected_floor = math.max(body_start, cell.finish - keep),
  }
end

return M
