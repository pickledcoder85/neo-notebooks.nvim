local exec = require("neo_notebooks.exec")
local output = require("neo_notebooks.output")

local M = {}

function M.restart(bufnr)
  bufnr = bufnr or 0
  exec.stop_session(bufnr)
  output.clear_all(bufnr)
  vim.notify("NeoNotebook: Python session restarted", vim.log.levels.INFO)
end

return M
