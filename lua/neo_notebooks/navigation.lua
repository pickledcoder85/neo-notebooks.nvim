local cells = require("neo_notebooks.cells")

local M = {}

local function get_sorted_cells(bufnr)
  return cells.get_cells(bufnr)
end

function M.next_cell(bufnr)
  bufnr = bufnr or 0
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local list = get_sorted_cells(bufnr)
  for _, cell in ipairs(list) do
    if cell.finish > line then
      local target = math.min(cell.finish, cell.start + 1)
      vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
      return
    end
  end
end

function M.prev_cell(bufnr)
  bufnr = bufnr or 0
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local list = get_sorted_cells(bufnr)
  for i = #list, 1, -1 do
    if list[i].start < line then
      local target = math.min(list[i].finish, list[i].start + 1)
      vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
      return
    end
  end
end

function M.cell_list(bufnr)
  bufnr = bufnr or 0
  local list = get_sorted_cells(bufnr)
  local items = {}

  for idx, cell in ipairs(list) do
    local header = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.start + 1, false)[1] or ""
    local title = header
    if cell.type == "markdown" then
      local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
      for _, line in ipairs(lines) do
        local trimmed = line:gsub("^%s+", "")
        if trimmed ~= "" then
          title = trimmed
          break
        end
      end
    end

    table.insert(items, string.format("%02d [%s] %s", idx, cell.type, title))
  end

  vim.ui.select(items, { prompt = "Cells" }, function(choice, idx)
    if not choice or not idx then
      return
    end
    local cell = list[idx]
    if cell then
      vim.api.nvim_win_set_cursor(0, { cell.start + 1, 0 })
    end
  end)
end

return M
