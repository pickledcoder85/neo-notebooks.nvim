local cells = require("neo_notebooks.cells")

local M = {}

function M.show(bufnr)
  bufnr = bufnr or 0
  local list = cells.get_cells(bufnr)
  local code = 0
  local markdown = 0
  for _, cell in ipairs(list) do
    if cell.type == "markdown" then
      markdown = markdown + 1
    else
      code = code + 1
    end
  end

  vim.notify(string.format("NeoNotebook: %d cells (%d code, %d markdown)", #list, code, markdown), vim.log.levels.INFO)
end

return M
