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
  local win_width = vim.api.nvim_win_get_width(0)
  local ratio = config.cell_width_ratio or 0.9
  local width = math.floor(win_width * ratio)
  width = math.max(config.cell_min_width or 60, width)
  width = math.min(config.cell_max_width or win_width, width)
  width = math.min(width, win_width)
  width = math.max(10, width)
  local pad = math.max(0, math.floor((win_width - width) / 2))
  local cells_list = cells.get_cells(bufnr)

  for idx, cell in ipairs(cells_list) do
    if cell.finish < cell.start then
      goto continue
    end

    local top = string.rep(" ", pad) .. cell_border(width, "╭", "╮")
    local bottom = string.rep(" ", pad) .. cell_border(width, "╰", "╯")
    local label = string.format(" [%s] ", cell.type)
    if config.show_cell_index then
      label = string.format(" [%d %s] ", idx, cell.type)
    end

    local hl = config.border_hl_code or "Comment"
    if cell.type == "markdown" then
      hl = config.border_hl_markdown or hl
    end

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
      local left_col = pad
      local right_col = math.max(pad, pad + width - 1)
      local text_pad = string.rep(" ", pad + 1)
      for line = cell.start, cell.finish do
        vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {
          virt_text = { { text_pad, hl } },
          virt_text_pos = "inline",
          right_gravity = false,
        })
        vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {
          virt_text = { { "│", hl } },
          virt_text_pos = "overlay",
          virt_text_win_col = left_col,
        })
        vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {
          virt_text = { { "│", hl } },
          virt_text_pos = "overlay",
          virt_text_win_col = right_col,
        })
      end
    end

    ::continue::
  end
end

return M
