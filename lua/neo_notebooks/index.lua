local cells = require("neo_notebooks.cells")

local M = {}
M.ns = vim.api.nvim_create_namespace("neo_notebooks_cell_ids")

local function build_index(bufnr)
  bufnr = bufnr or 0
  local list = cells.get_cells(bufnr)
  local index = { list = {}, by_id = {} }
  local used = {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  local function find_or_create_id(line)
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, M.ns, { line, 0 }, { line, -1 }, { details = false })
    if #marks > 0 then
      return marks[1][1]
    end
    return vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {})
  end

  for i, cell in ipairs(list) do
    local line = math.min(cell.start, line_count - 1)
    local id = find_or_create_id(line)
    used[id] = true
    local entry = {
      id = id,
      type = cell.type,
      start = cell.start,
      finish = cell.finish,
      body_len = cell.finish - cell.start + 1,
      border = cell.border ~= false,
    }
    table.insert(index.list, entry)
    index.by_id[entry.id] = entry
  end

  local all = vim.api.nvim_buf_get_extmarks(bufnr, M.ns, 0, -1, {})
  for _, mark in ipairs(all) do
    local id = mark[1]
    if not used[id] then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, id)
    end
  end

  return index
end

function M.get(bufnr)
  bufnr = bufnr or 0
  local state = vim.b[bufnr].neo_notebooks_index
  if not state then
    state = build_index(bufnr)
    vim.b[bufnr].neo_notebooks_index = state
  end
  return state
end

function M.rebuild(bufnr)
  bufnr = bufnr or 0
  local state = build_index(bufnr)
  vim.b[bufnr].neo_notebooks_index = state
  return state
end

function M.find_cell(bufnr, line)
  bufnr = bufnr or 0
  local state = M.get(bufnr)
  for _, cell in ipairs(state.list) do
    if line >= cell.start and line <= cell.finish then
      return cell
    end
  end
  return state.list[#state.list]
end

function M.get_by_id(bufnr, id)
  bufnr = bufnr or 0
  local state = M.get(bufnr)
  return state.by_id[id]
end

return M
