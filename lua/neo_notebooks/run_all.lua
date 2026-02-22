local cells = require("neo_notebooks.cells")
local exec = require("neo_notebooks.exec")
local output = require("neo_notebooks.output")
local config = require("neo_notebooks").config

local M = {}

function M.run_all(bufnr)
  bufnr = bufnr or 0
  local list = cells.get_cells(bufnr)
  for _, cell in ipairs(list) do
    if cell.type == "code" then
      local line = cell.start + 1
      if config.output == "inline" then
        exec.run_cell(bufnr, line, {
          on_output = function(lines, cell_id)
            output.show_inline(bufnr, {
              id = cell_id or cell.id,
              start = cell.start,
              finish = cell.finish,
              type = cell.type,
            }, lines)
          end,
          cell_id = cell.id,
        })
      else
        exec.run_cell(bufnr, line)
      end
    end
  end
end

return M
