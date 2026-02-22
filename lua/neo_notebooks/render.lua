local cells = require("neo_notebooks.cells")

local M = {}

M.ns = vim.api.nvim_create_namespace("neo_notebooks_cells")

local function cell_border(width, left, right)
  if width < 2 then
    return left .. right
  end
  return left .. string.rep("-", width - 2) .. right
end

function M.clear(bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
end

function M.render(bufnr)
  bufnr = bufnr or 0
  M.clear(bufnr)
  local width = math.max(10, vim.api.nvim_win_get_width(0) - 2)
  local cells_list = cells.get_cells(bufnr)

  for _, cell in ipairs(cells_list) do
    if cell.finish < cell.start then
      goto continue
    end

    local top = cell_border(math.min(width, width), "+", "+")
    local bottom = cell_border(math.min(width, width), "+", "+")
    local label = string.format(" [%s] ", cell.type)

    vim.api.nvim_buf_set_extmark(bufnr, M.ns, cell.start, 0, {
      virt_lines = { { { top, "Comment" } } },
      virt_lines_above = true,
      virt_text = { { label, "Identifier" } },
      virt_text_pos = "eol",
    })

    vim.api.nvim_buf_set_extmark(bufnr, M.ns, cell.finish, 0, {
      virt_lines = { { { bottom, "Comment" } } },
    })

    ::continue::
  end
end

return M
