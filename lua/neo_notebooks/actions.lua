local cells = require("neo_notebooks.cells")
local output = require("neo_notebooks.output")

local M = {}

function M.duplicate_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1

  local cell = cells.get_cell_at_line(bufnr, line)
  local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.finish + 1, false)
  local insert_at = cell.finish + 1

  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, lines)
  local new_start = insert_at
  vim.api.nvim_win_set_cursor(0, { new_start + 2, 0 })
  vim.cmd("startinsert")
end

function M.split_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1

  local cell = cells.get_cell_at_line(bufnr, line)
  if line <= cell.start then
    vim.notify("Place cursor inside the cell body to split", vim.log.levels.WARN)
    return
  end

  local marker = "# %% [" .. cell.type .. "]"
  vim.api.nvim_buf_set_lines(bufnr, line, line, false, { marker })
  vim.api.nvim_win_set_cursor(0, { line + 2, 0 })
  vim.cmd("startinsert")
end

function M.clear_output(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  output.clear_cell(bufnr, cell.start)
end

function M.delete_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  vim.api.nvim_buf_set_lines(bufnr, cell.start, cell.finish + 1, false, {})
  vim.api.nvim_win_set_cursor(0, { math.max(1, cell.start + 1), 0 })
  vim.cmd("startinsert")
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
