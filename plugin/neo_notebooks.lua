local nb = require("neo_notebooks")
local cells = require("neo_notebooks.cells")
local render = require("neo_notebooks.render")
local exec = require("neo_notebooks.exec")
local markdown = require("neo_notebooks.markdown")
local output = require("neo_notebooks.output")
local overlay = require("neo_notebooks.overlay")
local navigation = require("neo_notebooks.navigation")
local actions = require("neo_notebooks.actions")
local ipynb = require("neo_notebooks.ipynb")
local run_all = require("neo_notebooks.run_all")
local session = require("neo_notebooks.session")
local stats = require("neo_notebooks.stats")
local run_subset = require("neo_notebooks.run_subset")
local help = require("neo_notebooks.help")
local editor = require("neo_notebooks.editor")
local index = require("neo_notebooks.index")

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

local function buffer_is_empty(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines == 0 then
    return true
  end
  if #lines == 1 and lines[1] == "" then
    return true
  end
  return false
end

local function ensure_initial_markdown_cell(bufnr)
  if not nb.config.auto_insert_first_cell then
    return
  end
  if not should_enable(bufnr) then
    return
  end
  if not buffer_is_empty(bufnr) then
    return
  end
  if cells.has_markers(bufnr) then
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "# %% [markdown]", "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("startinsert")
end

local function update_completion(bufnr)
  if not nb.config.suppress_completion_in_markdown then
    return
  end
  if not should_enable(bufnr) then
    return
  end
  if bufnr ~= vim.api.nvim_get_current_buf() then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if not cell then
    return
  end

  local b = vim.b[bufnr]
  if cell.type == "markdown" then
    if b.completion ~= false then
      b.neo_notebooks_completion_prev = b.completion
      b.completion = false
      b.neo_notebooks_completion_forced = true
    end
  else
    if b.neo_notebooks_completion_forced then
      if b.neo_notebooks_completion_prev == nil then
        b.completion = nil
      else
        b.completion = b.neo_notebooks_completion_prev
      end
      b.neo_notebooks_completion_prev = nil
      b.neo_notebooks_completion_forced = nil
    end
  end
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
  vim.cmd("startinsert")
end, { nargs = "?", complete = function() return { "code", "markdown" } end })

vim.api.nvim_create_user_command("NeoNotebookCellToggleType", function()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  cells.toggle_cell_type(0, line)
  render_if_enabled(0)
end, {})

local function run_cell_with_output(line, cell)
  if nb.config.output == "inline" then
    exec.run_cell(0, line, {
      on_output = function(lines, cell_id)
        output.show_inline(0, {
          id = cell_id or cell.id,
          start = cell.start,
          finish = cell.finish,
          type = cell.type,
        }, lines)
      end,
      cell_id = cell.id,
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
  local list = cells.get_cells(0)
  local next_cell = nil
  for i, item in ipairs(list) do
    if item.start == cell.start then
      next_cell = list[i + 1]
      break
    end
  end

  if cell.type == "markdown" then
    if next_cell then
      vim.api.nvim_win_set_cursor(0, { next_cell.start + 2, 0 })
      vim.cmd("startinsert")
    else
      local insert_line = cells.insert_cell_below(0, cell.finish, "code")
      vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
      render_if_enabled(0)
      vim.cmd("startinsert")
    end
    return
  end

  run_cell_with_output(line, cell)

  if next_cell then
    vim.api.nvim_win_set_cursor(0, { next_cell.start + 2, 0 })
    vim.cmd("startinsert")
  else
    local insert_line = cells.insert_cell_below(0, cell.finish, "code")
    vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
    render_if_enabled(0)
    vim.cmd("startinsert")
  end
end, {})

vim.api.nvim_create_user_command("NeoNotebookMarkdownPreview", function()
  markdown.preview_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellOverlayToggle", function()
  overlay.toggle(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookAutoRenderToggle", function()
  actions.toggle_auto_render()
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellNext", function()
  navigation.next_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellPrev", function()
  navigation.prev_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellList", function()
  navigation.cell_list(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellDuplicate", function()
  actions.duplicate_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellSplit", function()
  actions.split_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellFold", function()
  actions.fold_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellUnfold", function()
  actions.unfold_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellFoldToggle", function()
  actions.toggle_fold_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookOutputClear", function()
  actions.clear_output(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookOutputClearAll", function()
  actions.clear_all_output(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellDelete", function()
  actions.delete_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellYank", function()
  actions.yank_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellMoveUp", function()
  actions.move_cell_up(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellMoveDown", function()
  actions.move_cell_down(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookRunAll", function()
  run_all.run_all(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookRestart", function()
  session.restart(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookOutputToggle", function()
  actions.toggle_output_mode()
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellSelect", function()
  actions.select_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookStats", function()
  stats.show(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookRunAbove", function()
  run_subset.run_above(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookRunBelow", function()
  run_subset.run_below(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookHelp", function()
  help.show()
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellEdit", function()
  editor.edit_cell(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellSave", function()
  editor.save_current()
end, {})

vim.api.nvim_create_user_command("NeoNotebookCellRunFromEditor", function()
  editor.run_from_editor()
end, {})

vim.api.nvim_create_user_command("NeoNotebookImportIpynb", function(opts)
  local path = opts.args
  if path == "" then
    vim.notify("Provide a .ipynb path", vim.log.levels.WARN)
    return
  end
  local ok, err = ipynb.import_ipynb(path, 0)
  if not ok then
    vim.notify(err or "Import failed", vim.log.levels.ERROR)
    return
  end
  render_if_enabled(0)
end, { nargs = 1, complete = "file" })

vim.api.nvim_create_user_command("NeoNotebookOpenIpynb", function(opts)
  local path = opts.args
  if path == "" then
    vim.notify("Provide a .ipynb path", vim.log.levels.WARN)
    return
  end
  local ok, err = ipynb.open_ipynb(path)
  if not ok then
    vim.notify(err or "Open failed", vim.log.levels.ERROR)
  end
end, { nargs = 1, complete = "file" })

vim.api.nvim_create_user_command("NeoNotebookExportIpynb", function(opts)
  local path = opts.args
  if path == "" then
    vim.notify("Provide a .ipynb path", vim.log.levels.WARN)
    return
  end
  local ok, err = ipynb.export_ipynb(path, 0)
  if not ok then
    vim.notify(err or "Export failed", vim.log.levels.ERROR)
  end
end, { nargs = 1, complete = "file" })

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
      vim.cmd("startinsert")
    end, opts)
  end

  if maps.new_markdown then
    vim.keymap.set("n", maps.new_markdown, function()
      local line = vim.api.nvim_win_get_cursor(0)[1] - 1
      local insert_line = cells.insert_cell_below(0, line, "markdown")
      vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
      render_if_enabled(0)
      vim.cmd("startinsert")
    end, opts)
  end

  if maps.run then
    vim.keymap.set("n", maps.run, function()
      vim.cmd("NeoNotebookCellRun")
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

  if maps.next_cell then
    vim.keymap.set("n", maps.next_cell, function()
      navigation.next_cell(0)
    end, opts)
  end

  if maps.prev_cell then
    vim.keymap.set("n", maps.prev_cell, function()
      navigation.prev_cell(0)
    end, opts)
  end

  if maps.cell_list then
    vim.keymap.set("n", maps.cell_list, function()
      navigation.cell_list(0)
    end, opts)
  end

  if maps.duplicate_cell then
    vim.keymap.set("n", maps.duplicate_cell, function()
      actions.duplicate_cell(0)
    end, opts)
  end

  if maps.split_cell then
    vim.keymap.set("n", maps.split_cell, function()
      actions.split_cell(0)
    end, opts)
  end

  if maps.fold_cell then
    vim.keymap.set("n", maps.fold_cell, function()
      actions.fold_cell(0)
    end, opts)
  end

  if maps.unfold_cell then
    vim.keymap.set("n", maps.unfold_cell, function()
      actions.unfold_cell(0)
    end, opts)
  end

  if maps.toggle_fold then
    vim.keymap.set("n", maps.toggle_fold, function()
      actions.toggle_fold_cell(0)
    end, opts)
  end

  if maps.clear_output then
    vim.keymap.set("n", maps.clear_output, function()
      actions.clear_output(0)
    end, opts)
  end

  if maps.clear_all_output then
    vim.keymap.set("n", maps.clear_all_output, function()
      actions.clear_all_output(0)
    end, opts)
  end

  if maps.delete_cell then
    vim.keymap.set("n", maps.delete_cell, function()
      actions.delete_cell(0)
    end, opts)
  end

  if maps.yank_cell then
    vim.keymap.set("n", maps.yank_cell, function()
      actions.yank_cell(0)
    end, opts)
  end

  if maps.move_up then
    vim.keymap.set("n", maps.move_up, function()
      actions.move_cell_up(0)
    end, opts)
  end

  if maps.move_down then
    vim.keymap.set("n", maps.move_down, function()
      actions.move_cell_down(0)
    end, opts)
  end

  if maps.run_all then
    vim.keymap.set("n", maps.run_all, function()
      run_all.run_all(0)
    end, opts)
  end

  if maps.restart then
    vim.keymap.set("n", maps.restart, function()
      session.restart(0)
    end, opts)
  end

  if maps.toggle_output then
    vim.keymap.set("n", maps.toggle_output, function()
      actions.toggle_output_mode()
    end, opts)
  end

  if maps.select_cell then
    vim.keymap.set("n", maps.select_cell, function()
      actions.select_cell(0)
    end, opts)
  end

  if maps.stats then
    vim.keymap.set("n", maps.stats, function()
      stats.show(0)
    end, opts)
  end

  if maps.run_above then
    vim.keymap.set("n", maps.run_above, function()
      run_subset.run_above(0)
    end, opts)
  end

  if maps.run_below then
    vim.keymap.set("n", maps.run_below, function()
      run_subset.run_below(0)
    end, opts)
  end

  if maps.toggle_auto_render then
    vim.keymap.set("n", maps.toggle_auto_render, function()
      actions.toggle_auto_render()
    end, opts)
  end

  if maps.toggle_overlay then
    vim.keymap.set("n", maps.toggle_overlay, function()
      overlay.toggle(0)
    end, opts)
  end

  if maps.help then
    vim.keymap.set("n", maps.help, function()
      help.show()
    end, opts)
  end

  if maps.edit_cell then
    vim.keymap.set("n", maps.edit_cell, function()
      editor.edit_cell(0)
    end, opts)
  end

  if maps.save_cell then
    vim.keymap.set("n", maps.save_cell, function()
      editor.save_current()
    end, opts)
  end

  if maps.run_cell then
    vim.keymap.set("n", maps.run_cell, function()
      editor.run_from_editor()
    end, opts)
  end
end

nb._on_setup = function()
  set_default_keymaps(0)
end

vim.api.nvim_create_autocmd({ "FileType" }, {
  callback = function(args)
    ensure_initial_markdown_cell(args.buf)
    if nb.config.overlay_preview and should_enable(args.buf) then
      overlay.enable(args.buf)
    end
  end,
})

vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }, {
  callback = function(args)
    overlay.on_cursor_moved(args.buf)
    update_completion(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
  callback = function(args)
    if should_enable(args.buf) then
      index.rebuild(args.buf)
    end
  end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
  callback = function(args)
    set_default_keymaps(args.buf)
    if should_enable(args.buf) then
      index.rebuild(args.buf)
    end
  end,
})
vim.api.nvim_create_autocmd({ "InsertEnter" }, {
  callback = function(args)
    update_completion(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
  callback = function(args)
    overlay.disable(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "BufWipeout" }, {
  callback = function(args)
    exec.stop_session(args.buf)
    output.clear_all(args.buf)
  end,
})

set_default_keymaps(0)
