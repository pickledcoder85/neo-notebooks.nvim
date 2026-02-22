local M = {}

local MARKER_PATTERN = "^# %%%% %[(%w+)%]%s*$"

local function normalize_cell_type(cell_type)
  if cell_type == nil or cell_type == "" then
    return "code"
  end
  cell_type = cell_type:lower()
  if cell_type ~= "code" and cell_type ~= "markdown" then
    return "code"
  end
  return cell_type
end

function M.get_cells(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cells = {}
  local current_type = "code"

  for i, line in ipairs(lines) do
    local cell_type = line:match(MARKER_PATTERN)
    if cell_type then
      local start_line = i - 1
      if #cells == 0 and start_line > 0 then
        table.insert(cells, {
          start = 0,
          finish = start_line - 1,
          type = current_type,
          border = false,
        })
      end

      if #cells > 0 then
        cells[#cells].finish = start_line - 1
      end

      current_type = normalize_cell_type(cell_type)
      table.insert(cells, {
        start = start_line,
        finish = #lines - 1,
        type = current_type,
        border = true,
      })
    end
  end

  if #cells == 0 then
    table.insert(cells, {
      start = 0,
      finish = #lines - 1,
      type = "markdown",
      border = true,
    })
  end

  return cells
end

function M.get_cells_indexed(bufnr)
  local index = require("neo_notebooks.index")
  return index.get(bufnr)
end

function M.get_cell_at_line(bufnr, line)
  local index = vim.b[bufnr] and vim.b[bufnr].neo_notebooks_index
  if index then
    for _, cell in ipairs(index.list) do
      if line >= cell.start and line <= cell.finish then
        return cell
      end
    end
    return index.list[#index.list]
  end

  local list = M.get_cells(bufnr)
  for _, cell in ipairs(list) do
    if line >= cell.start and line <= cell.finish then
      return cell
    end
  end
  return list[#list]
end

function M.insert_cell_below(bufnr, line, cell_type)
  bufnr = bufnr or 0
  local marker = "# %% [" .. normalize_cell_type(cell_type) .. "]"
  local insert_line = line + 1
  vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, { marker, "" })
  local index = require("neo_notebooks.index")
  index.rebuild(bufnr)
  return insert_line
end

function M.toggle_cell_type(bufnr, line)
  bufnr = bufnr or 0
  local cell = M.get_cell_at_line(bufnr, line)
  local marker_line = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.start + 1, false)[1]
  if marker_line == nil then
    return
  end

  local current = marker_line:match(MARKER_PATTERN)
  if not current then
    vim.api.nvim_buf_set_lines(bufnr, cell.start, cell.start + 1, false, { "# %% [code]" })
    return
  end

  local next_type = current == "code" and "markdown" or "code"
  vim.api.nvim_buf_set_lines(bufnr, cell.start, cell.start + 1, false, { "# %% [" .. next_type .. "]" })
end

function M.is_markdown_cell(bufnr, line)
  local cell = M.get_cell_at_line(bufnr, line)
  return cell.type == "markdown"
end

function M.get_cell_code(bufnr, line)
  local cell = M.get_cell_at_line(bufnr, line)
  if cell.type ~= "code" then
    return nil, "Current cell is markdown"
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
  return table.concat(lines, "\n"), nil
end

function M.get_cell_markdown(bufnr, line)
  local cell = M.get_cell_at_line(bufnr, line)
  if cell.type ~= "markdown" then
    return nil, "Current cell is code"
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
  return table.concat(lines, "\n"), nil
end

function M.has_markers(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:match(MARKER_PATTERN) then
      return true
    end
  end
  return false
end

return M
