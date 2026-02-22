local cells = require("neo_notebooks.cells")

local M = {}

local function build_index(bufnr)
  bufnr = bufnr or 0
  local list = cells.get_cells(bufnr)
  local index = { list = {}, by_id = {} }
  for i, cell in ipairs(list) do
    local entry = {
      id = i,
      type = cell.type,
      start = cell.start,
      finish = cell.finish,
    }
    table.insert(index.list, entry)
    index.by_id[entry.id] = entry
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
