local M = {}

M.ns = vim.api.nvim_create_namespace("neo_notebooks_output")

local function get_state(bufnr)
  if not vim.b[bufnr].neo_notebooks_output then
    vim.b[bufnr].neo_notebooks_output = {}
  end
  return vim.b[bufnr].neo_notebooks_output
end

function M.clear_cell(bufnr, cell_start)
  bufnr = bufnr or 0
  local state = get_state(bufnr)
  local id = state[cell_start]
  if id then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, id)
    state[cell_start] = nil
  end
end

function M.clear_all(bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  vim.b[bufnr].neo_notebooks_output = {}
end

function M.show_inline(bufnr, cell, lines)
  bufnr = bufnr or 0
  if not lines or #lines == 0 then
    return
  end

  M.clear_cell(bufnr, cell.start)

  local virt_lines = {}
  for _, line in ipairs(lines) do
    table.insert(virt_lines, { { line, "Comment" } })
  end

  local id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, cell.finish, 0, {
    virt_lines = virt_lines,
  })

  local state = get_state(bufnr)
  state[cell.start] = id
end

return M
