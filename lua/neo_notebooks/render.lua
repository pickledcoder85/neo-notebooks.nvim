local cells = require("neo_notebooks.cells")
local config = require("neo_notebooks").config

local M = {}

M.ns = vim.api.nvim_create_namespace("neo_notebooks_cells")

local function cell_border(width, left, right)
  if width < 2 then
    return left .. right
  end
  return left .. string.rep("─", width - 2) .. right
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

  for idx, cell in ipairs(cells_list) do
    if cell.finish < cell.start then
      goto continue
    end

    local top = cell_border(math.min(width, width), "╭", "╮")
    local bottom = cell_border(math.min(width, width), "╰", "╯")
    local label = string.format(" [%s] ", cell.type)
    if config.show_cell_index then
      label = string.format(" [%d %s] ", idx, cell.type)
    end

    local hl = config.border_hl or "Comment"

    vim.api.nvim_buf_set_extmark(bufnr, M.ns, cell.start, 0, {
      virt_lines = { { { top, hl } } },
      virt_lines_above = true,
      virt_text = { { label, "Identifier" } },
      virt_text_pos = "eol",
    })

    vim.api.nvim_buf_set_extmark(bufnr, M.ns, cell.finish, 0, {
      virt_lines = { { { bottom, hl } } },
    })

    if config.vertical_borders then
      for line = cell.start, cell.finish do
        vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {
          virt_text = { { "│", hl } },
          virt_text_pos = "inline",
          right_gravity = false,
        })
        vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {
          virt_text = { { "│", hl } },
          virt_text_pos = "right_align",
        })
      end
    end

    ::continue::
  end
end

return M
