local M = {}

M.ns = vim.api.nvim_create_namespace("neo_notebooks_output")

local function get_store(bufnr)
  if not vim.b[bufnr].neo_notebooks_output_store then
    vim.b[bufnr].neo_notebooks_output_store = {}
  end
  return vim.b[bufnr].neo_notebooks_output_store
end

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
  vim.b[bufnr].neo_notebooks_output_store = {}
end

function M.show_inline(bufnr, cell, lines)
  bufnr = bufnr or 0
  if not lines or #lines == 0 then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return
  end

  if cell.id then
    local store = get_store(bufnr)
    store[cell.id] = lines
  end

  M.render_outputs(bufnr)
end

function M.render_outputs(bufnr)
  bufnr = bufnr or 0
  local store = get_store(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  vim.b[bufnr].neo_notebooks_output = {}

  local index = require("neo_notebooks.index")
  local state = index.get(bufnr)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return
  end

  local config = require("neo_notebooks").config
  local win_width = vim.api.nvim_win_get_width(0)
  local ratio = config.cell_width_ratio or 0.9
  local width = math.floor(win_width * ratio)
  width = math.max(config.cell_min_width or 60, width)
  width = math.min(config.cell_max_width or win_width, width)
  width = math.min(width, win_width)
  width = math.max(10, width)
  local pad = math.max(0, math.floor((win_width - width) / 2))

  local function border(left, right)
    if width < 2 then
      return left .. right
    end
    return string.rep(" ", pad) .. left .. string.rep("─", width - 2) .. right
  end

  for _, cell in ipairs(state.list) do
    local lines = store[cell.id]
    if lines and #lines > 0 then
      local top = border("╰", "╯")
      local bottom = border("╰", "╯")
      local hl = "NeoNotebookOutput"
      local virt_lines = {}
      table.insert(virt_lines, { { top, hl } })
      for _, line in ipairs(lines) do
        local padded = string.rep(" ", pad + 1) .. line
        table.insert(virt_lines, { { padded, hl } })
      end
      table.insert(virt_lines, { { bottom, hl } })

      local target = math.min(math.max(0, cell.finish), line_count - 1)
      vim.api.nvim_buf_set_extmark(bufnr, M.ns, target, 0, {
        virt_lines = virt_lines,
      })
    end
  end
end

return M
