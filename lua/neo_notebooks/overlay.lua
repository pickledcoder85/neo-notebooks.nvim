local cells = require("neo_notebooks.cells")

local M = {}

local function get_state(bufnr)
  if not vim.b[bufnr].neo_notebooks_overlay then
    vim.b[bufnr].neo_notebooks_overlay = {
      win = nil,
      buf = nil,
      cell_start = nil,
    }
  end
  return vim.b[bufnr].neo_notebooks_overlay
end

local function close_overlay(state)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.cell_start = nil
end

local function ensure_window(bufnr, state, width, height)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_set_config(state.win, {
      relative = "editor",
      row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
      col = math.max(1, math.floor((vim.o.columns - width) / 2)),
      width = width,
      height = height,
    })
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "single",
  })

  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "linebreak", true)

  state.win = win
  state.buf = buf
end

local function update_overlay(bufnr, state)
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if not cell then
    return
  end

  if state.cell_start == cell.start and state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.finish + 1, false)
  if #lines == 0 then
    return
  end

  local width = math.min(vim.o.columns - 6, 100)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))

  ensure_window(bufnr, state, width, height)

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  state.cell_start = cell.start
end

function M.enable(bufnr)
  bufnr = bufnr or 0
  local state = get_state(bufnr)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return
  end
  if vim.api.nvim_get_option_value("buftype", { buf = bufnr }) ~= "" then
    return
  end
  update_overlay(bufnr, state)
end

function M.disable(bufnr)
  bufnr = bufnr or 0
  local state = get_state(bufnr)
  close_overlay(state)
end

function M.toggle(bufnr)
  bufnr = bufnr or 0
  local state = get_state(bufnr)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    close_overlay(state)
  else
    update_overlay(bufnr, state)
  end
end

function M.on_cursor_moved(bufnr)
  bufnr = bufnr or 0
  local state = get_state(bufnr)
  if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
    return
  end
  update_overlay(bufnr, state)
end

return M
