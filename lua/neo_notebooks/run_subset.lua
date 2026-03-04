local cells = require("neo_notebooks.cells")
local exec = require("neo_notebooks.exec")
local output = require("neo_notebooks.output")
local config = require("neo_notebooks").config

local M = {}

local function run_cell(bufnr, cell)
  local line = cell.start + 1
  local index = require("neo_notebooks.index")
  local entry = index.find_cell(bufnr, line)
  if entry then
    cell.id = entry.id
    cell.start = entry.start
    cell.finish = entry.finish
  end
  if config.output == "inline" then
    exec.run_cell(bufnr, line, {
      on_output = function(payload, cell_id, duration_ms)
        output.show_payload(bufnr, {
          id = cell_id or cell.id,
          start = cell.start,
          finish = cell.finish,
          type = cell.type,
        }, payload, { duration_ms = duration_ms })
      end,
      cell_id = cell.id,
    })
  else
    exec.run_cell(bufnr, line)
  end
end

function M.run_above(bufnr, line)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local current = cells.get_cell_at_line(bufnr, line)
  local upper_bound = current and current.start or line
  local list = cells.get_cells(bufnr)
  for _, cell in ipairs(list) do
    if cell.type == "code" and cell.finish < upper_bound then
      run_cell(bufnr, cell)
    end
  end
end

function M.run_below(bufnr, line)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local current = cells.get_cell_at_line(bufnr, line)
  local current_start = current and current.start or line
  local list = cells.get_cells(bufnr)
  for _, cell in ipairs(list) do
    if cell.type == "code" and cell.start >= current_start then
      run_cell(bufnr, cell)
    end
  end
end

return M
