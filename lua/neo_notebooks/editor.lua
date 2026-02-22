local cells = require("neo_notebooks.cells")
local exec = require("neo_notebooks.exec")
local output = require("neo_notebooks.output")
local config = require("neo_notebooks").config

local M = {}

local function open_editor(bufnr, cell)
  local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  local ft = cell.type == "markdown" and "markdown" or "python"
  vim.api.nvim_set_option_value("filetype", ft, { buf = buf })

  local width = math.min(vim.o.columns - 6, 100)
  local height = math.min(#lines + 4, math.floor(vim.o.lines * 0.7))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "single",
  })

  vim.api.nvim_win_set_option(win, "wrap", true)

  vim.b[buf].neo_notebooks_editor = {
    source_buf = bufnr,
    cell_start = cell.start,
    cell_finish = cell.finish,
    cell_type = cell.type,
    cell_id = cell.id,
  }

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true })

  return buf, win
end

local function save_editor(buf)
  local state = vim.b[buf].neo_notebooks_editor
  if not state then
    return nil, "Not a NeoNotebook editor"
  end

  local source = state.source_buf
  if not vim.api.nvim_buf_is_valid(source) then
    return nil, "Source buffer is no longer valid"
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local index = require("neo_notebooks.index")
  local entry = index.get_by_id(source, state.cell_id)
  if entry then
    state.cell_start = entry.start
    state.cell_finish = entry.finish
  end
  vim.api.nvim_buf_set_lines(source, state.cell_start + 1, state.cell_finish + 1, false, lines)
  return true
end

function M.edit_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if not cell then
    return
  end
  open_editor(bufnr, cell)
end

function M.save_current()
  local buf = vim.api.nvim_get_current_buf()
  local ok, err = save_editor(buf)
  if not ok then
    vim.notify(err or "Save failed", vim.log.levels.ERROR)
    return
  end
  vim.notify("NeoNotebook: cell saved", vim.log.levels.INFO)
end

function M.run_from_editor()
  local buf = vim.api.nvim_get_current_buf()
  local state = vim.b[buf].neo_notebooks_editor
  if not state then
    vim.notify("Not a NeoNotebook editor", vim.log.levels.ERROR)
    return
  end
  local ok, err = save_editor(buf)
  if not ok then
    vim.notify(err or "Save failed", vim.log.levels.ERROR)
    return
  end

  if state.cell_type ~= "code" then
    vim.notify("Current cell is markdown", vim.log.levels.WARN)
    return
  end

  local index = require("neo_notebooks.index")
  local entry = index.get_by_id(state.source_buf, state.cell_id)
  if not entry then
    vim.notify("Cell not found", vim.log.levels.ERROR)
    return
  end
  state.cell_start = entry.start
  state.cell_finish = entry.finish
  local line = entry.start + 1
  if config.output == "inline" then
    exec.run_cell(state.source_buf, line, {
      on_output = function(lines)
        output.show_inline(state.source_buf, {
          start = state.cell_start,
          finish = state.cell_finish,
          type = state.cell_type,
        }, lines)
      end,
    })
  else
    exec.run_cell(state.source_buf, line)
  end
end

return M
