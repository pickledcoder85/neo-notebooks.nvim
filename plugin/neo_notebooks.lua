local nb = require("neo_notebooks")
local cells = require("neo_notebooks.cells")
local render = require("neo_notebooks.render")
local exec = require("neo_notebooks.exec")
local markdown = require("neo_notebooks.markdown")
local output = require("neo_notebooks.output")

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

local function run_cell_with_output(line, cell)
  if nb.config.output == "inline" then
    exec.run_cell(0, line, {
      on_output = function(lines)
        output.show_inline(0, cell, lines)
      end,
    })
  else
    exec.run_cell(0, line)
  end
end

vim.api.nvim_create_user_command("NeoNotebookCellRun", function()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(0, line)
  run_cell_with_output(line, cell)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellRunAndNext", function()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(0, line)

  if cell.type == "markdown" then
    local insert_line = cells.insert_cell_below(0, cell.finish, "code")
    vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
    render_if_enabled(0)
    vim.cmd("startinsert")
    return
  end

  run_cell_with_output(line, cell)

  local insert_line = cells.insert_cell_below(0, cell.finish, "code")
  vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
  render_if_enabled(0)
  vim.cmd("startinsert")
end, {})

vim.api.nvim_create_user_command("NeoNotebookMarkdownPreview", function()
  markdown.preview_cell(0)
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

  if maps.preview then
    vim.keymap.set("n", maps.preview, function()
      markdown.preview_cell(0)
    end, opts)
  end

  if maps.run_and_next then
    vim.keymap.set({ "n", "i" }, maps.run_and_next, function()
      vim.cmd("stopinsert")
      vim.cmd("NeoNotebookCellRunAndNext")
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
    output.clear_all(args.buf)
  end,
})

set_default_keymaps(0)
