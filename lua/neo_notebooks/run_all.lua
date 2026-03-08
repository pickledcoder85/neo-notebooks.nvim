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
    return exec.run_cell(bufnr, line, {
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
  end
  return exec.run_cell(bufnr, line)
end

function M.run_all(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local summary = {
    attempted = 0,
    queued = 0,
    failed = 0,
    first_err = nil,
    first_level = nil,
  }
  local list = cells.get_cells(bufnr)
  for _, cell in ipairs(list) do
    if cell.type == "code" then
      summary.attempted = summary.attempted + 1
      local ok, err, level = run_cell(bufnr, cell)
      if ok then
        summary.queued = summary.queued + 1
      else
        summary.failed = summary.failed + 1
        if not summary.first_err then
          summary.first_err = err or "Cell run failed"
          summary.first_level = level or vim.log.levels.WARN
        end
      end
    end
  end
  return summary
end

return M
