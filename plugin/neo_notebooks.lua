local nb = require("neo_notebooks")
local cells = require("neo_notebooks.cells")
local render = require("neo_notebooks.render")
local exec = require("neo_notebooks.exec")

local function has_filetype(bufnr)
  local allowed = nb.config.filetypes
  if not allowed or #allowed == 0 then
    return true
  end
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  for _, item in ipairs(allowed) do
    if ft == item then
      return true
    end
  end
  return false
end

local function should_enable(bufnr)
  bufnr = bufnr or 0
  if not has_filetype(bufnr) then
    return false
  end
  if nb.config.require_markers then
    return cells.has_markers(bufnr)
  end
  return true
end

local function render_if_enabled(bufnr)
  bufnr = bufnr or 0
  if nb.config.auto_render and should_enable(bufnr) then
    render.render(bufnr)
  end
end

vim.api.nvim_create_user_command("NeoNotebookRender", function()
  render.render(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellNew", function(opts)
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local insert_line = cells.insert_cell_below(0, line, opts.args)
  vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
  render_if_enabled(0)
end, { nargs = "?", complete = function() return { "code", "markdown" } end })

vim.api.nvim_create_user_command("NeoNotebookCellToggleType", function()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  cells.toggle_cell_type(0, line)
  render_if_enabled(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellRun", function()
  exec.run_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookEnable", function()
  render_if_enabled(0)
end, {})

vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
  callback = function(args)
    render_if_enabled(args.buf)
  end,
})

local function set_default_keymaps(bufnr)
  if nb.config.keymaps == false then
    return
  end

  bufnr = bufnr or 0
  if not should_enable(bufnr) then
    return
  end

  local maps = nb.config.keymaps or {}
  local opts = { noremap = true, silent = true, buffer = bufnr }

  if maps.new_code then
    vim.keymap.set("n", maps.new_code, function()
      local line = vim.api.nvim_win_get_cursor(0)[1] - 1
      local insert_line = cells.insert_cell_below(0, line, "code")
      vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
      render_if_enabled(0)
    end, opts)
  end

  if maps.new_markdown then
    vim.keymap.set("n", maps.new_markdown, function()
      local line = vim.api.nvim_win_get_cursor(0)[1] - 1
      local insert_line = cells.insert_cell_below(0, line, "markdown")
      vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
      render_if_enabled(0)
    end, opts)
  end

  if maps.run then
    vim.keymap.set("n", maps.run, function()
      exec.run_cell(0)
    end, opts)
  end

  if maps.toggle then
    vim.keymap.set("n", maps.toggle, function()
      local line = vim.api.nvim_win_get_cursor(0)[1] - 1
      cells.toggle_cell_type(0, line)
      render_if_enabled(0)
    end, opts)
  end
end

nb._on_setup = function()
  set_default_keymaps(0)
end

vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
  callback = function(args)
    set_default_keymaps(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "BufWipeout" }, {
  callback = function(args)
    exec.stop_session(args.buf)
  end,
})

set_default_keymaps(0)
