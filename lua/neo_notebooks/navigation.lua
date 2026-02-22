local cells = require("neo_notebooks.cells")
local config = require("neo_notebooks").config

local M = {}

local function get_sorted_cells(bufnr)
  return cells.get_cells(bufnr)
end

local function ensure_line_exists(bufnr, line)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line + 1 > line_count then
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, { "" })
  end
end

local function move_to_cell_start(bufnr, cell)
  local target = cell.start + 1
  ensure_line_exists(bufnr, target)
  vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
  if config.auto_insert_on_jump then
    vim.cmd("startinsert")
  end
end

local function current_cell_index(list, line)
  for i, cell in ipairs(list) do
    if line >= cell.start and line <= cell.finish then
      return i
    end
  end
  return nil
end

function M.next_cell(bufnr)
  bufnr = bufnr or 0
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local list = get_sorted_cells(bufnr)
  local idx = current_cell_index(list, line)
  if idx and list[idx + 1] then
    move_to_cell_start(bufnr, list[idx + 1])
  end
end

function M.prev_cell(bufnr)
  bufnr = bufnr or 0
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local list = get_sorted_cells(bufnr)
  local idx = current_cell_index(list, line)
  if idx and list[idx - 1] then
    move_to_cell_start(bufnr, list[idx - 1])
  end
end

function M.cell_list(bufnr)
  bufnr = bufnr or 0
  local list = get_sorted_cells(bufnr)
  local items = {}

  for idx, cell in ipairs(list) do
    local title = ""
    local body_lines = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
    for _, line in ipairs(body_lines) do
      local trimmed = line:gsub("^%s+", "")
      if trimmed ~= "" then
        title = trimmed
        break
      end
    end
    if title == "" then
      title = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.start + 1, false)[1] or ""
    end
    if #title > 60 then
      title = title:sub(1, 57) .. "..."
    end

    table.insert(items, string.format("%02d [%s] L%03d %s", idx, cell.type, cell.start + 1, title))
  end

  vim.ui.select(items, { prompt = "Cells" }, function(choice, idx)
    if not choice or not idx then
      return
    end
    local cell = list[idx]
    if cell then
      move_to_cell_start(bufnr, cell)
      vim.cmd("normal! zz")
    end
  end)
end

return M
