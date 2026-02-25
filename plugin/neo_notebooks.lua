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
local scheduler = require("neo_notebooks.scheduler")

local set_default_keymaps

local function has_filetype(bufnr)
  if vim.b[bufnr] and vim.b[bufnr].neo_notebooks_enabled then
    return true
  end
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
  if vim.b[bufnr] and vim.b[bufnr].neo_notebooks_skip_initial then
    return
  end
  if vim.b[bufnr] and vim.b[bufnr].neo_notebooks_is_ipynb then
    return
  end
  if vim.api.nvim_buf_get_option(bufnr, "buftype") == "acwrite" then
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
  if nb.config.suppress_completion_popup then
    if b.neo_notebooks_completion_forced ~= true then
      b.neo_notebooks_completion_prev = b.completion
      b.neo_notebooks_completion_forced = true
    end
    b.completion = false
    return
  end

  if cell.type == "markdown" then
    if b.completion ~= false then
      b.neo_notebooks_completion_prev = b.completion
      b.completion = false
      b.neo_notebooks_completion_forced = true
    end
    if b.neo_notebooks_prev_omnifunc == nil then
      b.neo_notebooks_prev_omnifunc = vim.bo[bufnr].omnifunc
      b.neo_notebooks_prev_completefunc = vim.bo[bufnr].completefunc
    end
    vim.bo[bufnr].omnifunc = ""
    vim.bo[bufnr].completefunc = ""
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
    if b.neo_notebooks_prev_omnifunc ~= nil then
      vim.bo[bufnr].omnifunc = b.neo_notebooks_prev_omnifunc
      vim.bo[bufnr].completefunc = b.neo_notebooks_prev_completefunc or ""
      b.neo_notebooks_prev_omnifunc = nil
      b.neo_notebooks_prev_completefunc = nil
    end
  end
end

local function update_textwidth(bufnr)
  if not nb.config.textwidth_in_cells then
    return
  end
  if not should_enable(bufnr) then
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if not cell then
    return
  end
  if not vim.b[bufnr].neo_notebooks_prev_textwidth then
    vim.b[bufnr].neo_notebooks_prev_textwidth = vim.bo[bufnr].textwidth
  end
  local inner_width = nil
  if cell.layout and cell.layout.left_col and cell.layout.right_col then
    inner_width = math.max(1, cell.layout.right_col - cell.layout.left_col - 1)
  else
    local win_width = vim.api.nvim_win_get_width(0)
    local ratio = nb.config.cell_width_ratio or 0.9
    local width = math.floor(win_width * ratio)
    width = math.max(nb.config.cell_min_width or 60, width)
    width = math.min(nb.config.cell_max_width or win_width, width)
    width = math.min(width, win_width)
    width = math.max(10, width)
    inner_width = math.max(1, width - 2)
  end
  vim.bo[bufnr].textwidth = inner_width
end

local function ensure_top_padding(bufnr)
  local pad = nb.config.top_padding or 0
  if pad <= 0 then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, pad, false)
  local missing = 0
  for i = 1, pad do
    if lines[i] ~= "" then
      missing = pad - (i - 1)
      break
    end
  end
  if missing > 0 then
    local blanks = {}
    for _ = 1, missing do
      table.insert(blanks, "")
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, blanks)
  end
end

local function trim_cell_spacing(bufnr)
  actions.normalize_spacing(bufnr)
end

local function render_if_enabled(bufnr)
  bufnr = bufnr or 0
  if nb.config.auto_render and should_enable(bufnr) then
    render.render(bufnr)
  end
end

local function logical_cell_insert_base(bufnr, cell)
  local body = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
  local last_nonempty = nil
  for i = #body, 1, -1 do
    if body[i] ~= "" then
      last_nonempty = cell.start + i
      break
    end
  end
  if not last_nonempty then
    return cell.start + 1
  end
  return last_nonempty + 1
end

vim.api.nvim_create_user_command("NeoNotebookRender", function()
  render.render(0)
end, {})


vim.api.nvim_create_user_command("NeoNotebookCellNew", function(opts)
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local insert_line = cells.insert_cell_below(0, line, opts.args)
  vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
  actions.clamp_cursor_to_cell_left(0, { force = true })
  render_if_enabled(0)
  vim.cmd("startinsert")
end, { nargs = "?", complete = function() return { "code", "markdown" } end })

vim.api.nvim_create_user_command("NeoNotebookCellToggleType", function()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  cells.toggle_cell_type(0, line)
  render_if_enabled(0)
end, {})

local function run_cell_with_output(line, cell)
  local bufnr = vim.api.nvim_get_current_buf()
  local index = require("neo_notebooks.index")
  local entry = index.find_cell(bufnr, line)
  if entry and not cell.id then
    cell.id = entry.id
    cell.start = entry.start
    cell.finish = entry.finish
  end
  if nb.config.output == "inline" then
    exec.run_cell(bufnr, line, {
      on_output = function(lines, cell_id, duration_ms)
        output.show_inline(bufnr, {
          id = cell_id or cell.id,
          start = cell.start,
          finish = cell.finish,
          type = cell.type,
        }, lines, { duration_ms = duration_ms })
      end,
      cell_id = cell.id,
    })
  else
    exec.run_cell(bufnr, line)
  end
end

vim.api.nvim_create_user_command("NeoNotebookCellRun", function()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(0, line)
  actions.consume_pending_virtual_indent(0)
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
      local max_line = vim.api.nvim_buf_line_count(0)
      local target = math.min(next_cell.start + 2, max_line)
      vim.api.nvim_win_set_cursor(0, { target, 0 })
      actions.clamp_cursor_to_cell_left(0, { force = true })
    else
      local insert_base = logical_cell_insert_base(0, cell)
      local insert_line = cells.insert_cell_below(0, insert_base, "code")
      local max_line = vim.api.nvim_buf_line_count(0)
      local target = math.min(insert_line + 2, max_line)
      vim.api.nvim_win_set_cursor(0, { target, 0 })
      render_if_enabled(0)
      actions.clamp_cursor_to_cell_left(0, { force = true })
      vim.cmd("startinsert")
    end
    return
  end

  if not next_cell and not actions.cell_has_nonempty_body(0, line) then
    vim.notify("NeoNotebook: current code cell is empty; not adding another cell", vim.log.levels.INFO)
    local max_line = vim.api.nvim_buf_line_count(0)
    local target = math.min(cell.start + 2, max_line)
    vim.api.nvim_win_set_cursor(0, { target, 0 })
    actions.clamp_cursor_to_cell_left(0, { force = true })
    vim.cmd("startinsert")
    return
  end

  actions.consume_pending_virtual_indent(0)
  run_cell_with_output(line, cell)

  if next_cell then
    local max_line = vim.api.nvim_buf_line_count(0)
    local target = math.min(next_cell.start + 2, max_line)
    vim.api.nvim_win_set_cursor(0, { target, 0 })
    actions.clamp_cursor_to_cell_left(0, { force = true })
  else
    local insert_base = logical_cell_insert_base(0, cell)
    local insert_line = cells.insert_cell_below(0, insert_base, "code")
    local max_line = vim.api.nvim_buf_line_count(0)
    local target = math.min(insert_line + 2, max_line)
    vim.api.nvim_win_set_cursor(0, { target, 0 })
    render_if_enabled(0)
    actions.clamp_cursor_to_cell_left(0)
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

vim.api.nvim_create_user_command("NeoNotebookCellIndexToggle", function()
  actions.toggle_cell_index()
  render_if_enabled(0)
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
  actions.consume_pending_virtual_indent(0)
  run_all.run_all(vim.api.nvim_get_current_buf())
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
  actions.consume_pending_virtual_indent(0)
  run_subset.run_above(vim.api.nvim_get_current_buf())
end, {})

vim.api.nvim_create_user_command("NeoNotebookRunBelow", function()
  actions.consume_pending_virtual_indent(0)
  run_subset.run_below(vim.api.nvim_get_current_buf())
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
  actions.consume_pending_virtual_indent(0)
  local ok, err = ipynb.export_ipynb(path, 0)
  if not ok then
    vim.notify(err or "Export failed", vim.log.levels.ERROR)
  end
end, { nargs = 1, complete = "file" })

vim.api.nvim_create_user_command("NeoNotebookEnable", function()
  render_if_enabled(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookOutputHasAnsi", function()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(0, line)
  if not cell or not cell.id then
    vim.notify("NeoNotebook: no cell id found", vim.log.levels.WARN)
    return
  end
  local lines = output.get_lines(0, cell.id)
  if not lines or #lines == 0 then
    vim.notify("NeoNotebook: no output for cell", vim.log.levels.INFO)
    return
  end
  local has_ansi, count = output.has_ansi(lines)
  if has_ansi then
    vim.notify("NeoNotebook: ANSI sequences found (" .. tostring(count) .. ")", vim.log.levels.INFO)
  else
    vim.notify("NeoNotebook: no ANSI sequences in output", vim.log.levels.WARN)
  end
end, {})

vim.api.nvim_create_user_command("NeoNotebookAnsiSample", function()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(0, line)
  if not cell or not cell.id then
    vim.notify("NeoNotebook: no cell id found", vim.log.levels.WARN)
    return
  end
  output.show_inline(0, cell, {
    "\27[1;36mANSI Cyan Bold\27[0m and \27[33mYellow\27[0m text",
  })
end, {})

vim.api.nvim_create_autocmd({ "BufEnter" }, {
  callback = function(args)
    render_if_enabled(args.buf)
  end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = "*.ipynb",
  callback = function(args)
    if not nb.config.auto_open_ipynb then
      return
    end
    if vim.b[args.buf].neo_notebooks_ipynb_opened then
      return
    end
    local path = vim.api.nvim_buf_get_name(args.buf)
    if path == "" then
      return
    end
    vim.b[args.buf].neo_notebooks_ipynb_opened = true
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(args.buf) then
        return
      end
      vim.b[args.buf].neo_notebooks_skip_initial = true
      vim.api.nvim_buf_set_option(args.buf, "buftype", "acwrite")
      vim.api.nvim_buf_set_option(args.buf, "swapfile", false)
      vim.api.nvim_buf_set_option(args.buf, "modifiable", true)
      vim.b[args.buf].neo_notebooks_is_ipynb = true
      vim.b[args.buf].neo_notebooks_enabled = true
      vim.api.nvim_set_option_value("filetype", "python", { buf = args.buf })
      local ok, err = ipynb.import_ipynb(path, args.buf)
      if not ok then
        vim.b[args.buf].neo_notebooks_skip_initial = false
        vim.notify(err or "Import failed", vim.log.levels.ERROR)
        return
      end
      ensure_top_padding(args.buf)
      vim.b[args.buf].neo_notebooks_skip_initial = true
      set_default_keymaps(args.buf)
      index.mark_dirty(args.buf)
      index.attach(args.buf)
      render_if_enabled(args.buf)
    end)
  end,
})

vim.api.nvim_create_autocmd("BufWriteCmd", {
  pattern = "*.ipynb",
  callback = function(args)
    local path = vim.api.nvim_buf_get_name(args.buf)
    if path == "" then
      return
    end
    local ok, err = ipynb.export_ipynb(path, args.buf)
    if not ok then
      vim.notify(err or "Export failed", vim.log.levels.ERROR)
      return
    end
    vim.api.nvim_buf_set_option(args.buf, "modified", false)
    vim.notify("NeoNotebook: wrote " .. path, vim.log.levels.INFO)
  end,
})

set_default_keymaps = function(bufnr)
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
      actions.clamp_cursor_to_cell_left(0, { force = true })
      render_if_enabled(0)
      vim.cmd("startinsert")
    end, opts)
  end

  if maps.new_markdown then
    vim.keymap.set("n", maps.new_markdown, function()
      local line = vim.api.nvim_win_get_cursor(0)[1] - 1
      local insert_line = cells.insert_cell_below(0, line, "markdown")
      vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
      actions.clamp_cursor_to_cell_left(0, { force = true })
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
      actions.move_cell_up(0, nil, vim.v.count1)
    end, opts)
  end

  if maps.move_down then
    vim.keymap.set("n", maps.move_down, function()
      actions.move_cell_down(0, nil, vim.v.count1)
    end, opts)
  end

  if maps.move_top then
    vim.keymap.set("n", maps.move_top, function()
      actions.move_cell_top(0)
    end, opts)
  end

  if maps.move_bottom then
    vim.keymap.set("n", maps.move_bottom, function()
      actions.move_cell_bottom(0)
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

  if nb.config.soft_contain then
    vim.keymap.set("n", "o", function()
      actions.open_line_below(bufnr)
    end, vim.tbl_extend("force", opts, { remap = true }))
    vim.keymap.set("n", "O", function()
      actions.open_line_above(bufnr)
    end, vim.tbl_extend("force", opts, { remap = true }))
    vim.keymap.set("n", "gg", function()
      actions.goto_cell_top(bufnr)
    end, opts)
    vim.keymap.set("n", "G", function()
      actions.goto_cell_bottom(bufnr)
    end, opts)
    if nb.config.contain_line_nav ~= false then
      vim.keymap.set("n", "j", function()
        actions.move_line_down_contained(bufnr, vim.v.count1)
      end, opts)
      vim.keymap.set("n", "k", function()
        actions.move_line_up_contained(bufnr, vim.v.count1)
      end, opts)
      vim.keymap.set("n", "_", function()
        actions.goto_line_first_nonblank_contained(bufnr)
      end, opts)
    end
    vim.keymap.set("n", "<CR>", function()
      actions.handle_enter_normal(bufnr)
    end, opts)
    vim.keymap.set("i", "<CR>", function()
      actions.handle_enter_insert(bufnr)
    end, { silent = true, buffer = bufnr })
    vim.keymap.set("i", "<BS>", function()
      return actions.guard_backspace_in_insert(bufnr)
    end, { silent = true, buffer = bufnr, expr = true })
    vim.keymap.set("i", "<Del>", function()
      return actions.guard_delete_in_insert(bufnr)
    end, { silent = true, buffer = bufnr, expr = true })
    vim.keymap.set("n", "dd", function()
      return actions.guard_delete_current_line(bufnr)
    end, { silent = true, buffer = bufnr, expr = true, replace_keycodes = false })
    vim.keymap.set("n", "d", function()
      actions.handle_delete_motion(bufnr)
    end, { silent = true, buffer = bufnr })
    vim.keymap.set("n", "p", function()
      actions.handle_paste_below(bufnr)
    end, opts)
    vim.keymap.set("n", "x", function()
      return actions.guard_delete_char(bufnr)
    end, { silent = true, buffer = bufnr, expr = true, replace_keycodes = false })
    vim.keymap.set("n", "D", function()
      return actions.guard_delete_to_eol(bufnr)
    end, { silent = true, buffer = bufnr, expr = true, replace_keycodes = false })
    vim.keymap.set("x", "d", function()
      return actions.guard_visual_delete(bufnr)
    end, { silent = true, buffer = bufnr, expr = true, replace_keycodes = false })
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
    update_textwidth(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
  callback = function(args)
    if should_enable(args.buf) then
      index.on_text_changed(args.buf)
      local dirty_cells = index.consume_dirty_cells(args.buf)
      local hint = index.consume_render_hint(args.buf)
      local insert_mode = vim.api.nvim_get_mode().mode:match("^i") ~= nil
      local immediate = hint == "immediate" or insert_mode
      if dirty_cells then
        scheduler.request_render(args.buf, { debounce_ms = immediate and 0 or 20, immediate = immediate, cell_ids = dirty_cells })
      else
        scheduler.request_render(args.buf, { debounce_ms = immediate and 0 or 20, immediate = immediate })
      end
    end
  end,
})

vim.api.nvim_create_autocmd({ "InsertLeave" }, {
  callback = function(args)
    if should_enable(args.buf) then
      actions.consume_pending_virtual_indent(args.buf)
    end
  end,
})

vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave" }, {
  callback = function(args)
    if should_enable(args.buf) and nb.config.auto_render then
      scheduler.request_render(args.buf, { immediate = true })
    end
  end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
  callback = function(args)
    set_default_keymaps(args.buf)
    if should_enable(args.buf) then
      ensure_top_padding(args.buf)
      trim_cell_spacing(args.buf)
      index.mark_dirty(args.buf)
      index.attach(args.buf)
      if nb.config.auto_render then
        scheduler.request_render(args.buf, { immediate = true })
      end
      if nb.config.notebook_scrolloff and nb.config.notebook_scrolloff > 0 then
        vim.api.nvim_set_option_value("scrolloff", nb.config.notebook_scrolloff, { win = 0 })
      end

      local function jump_to_first_body()
        if not vim.api.nvim_buf_is_valid(args.buf) then
          return
        end
        local state = index.get(args.buf)
        for _, entry in ipairs(state.list) do
          if entry.border ~= false then
            local target = math.min(entry.start + 1, entry.finish)
            vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
            return
          end
        end
      end

      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(args.buf) then
          return
        end
        local cur_line = vim.api.nvim_win_get_cursor(0)[1] - 1
        local cur_cell = cells.get_cell_at_line(args.buf, cur_line)
        if cur_cell and (cur_cell.border == false or cur_line == cur_cell.start) then
          jump_to_first_body()
          return
        end
        if not vim.b[args.buf].neo_notebooks_opened then
          vim.b[args.buf].neo_notebooks_opened = true
          jump_to_first_body()
        end
      end)
    end
  end,
})

vim.api.nvim_create_autocmd({ "WinEnter" }, {
  callback = function(args)
    if should_enable(args.buf) and nb.config.auto_render then
      scheduler.request_render(args.buf, { immediate = true })
    end
  end,
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.nn",
  callback = function(args)
    vim.b[args.buf].neo_notebooks_enabled = true
    vim.api.nvim_set_option_value("filetype", "python", { buf = args.buf })
  end,
})
vim.api.nvim_create_autocmd({ "InsertEnter" }, {
  callback = function(args)
    if should_enable(args.buf) then
      if nb.config.strict_containment == "soft" or nb.config.strict_containment == true then
        actions.contain_insert_entry(args.buf)
      end
    end
    update_completion(args.buf)
    update_textwidth(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "InsertLeave" }, {
  callback = function(args)
    if not should_enable(args.buf) then
      return
    end
    vim.b[args.buf].neo_notebooks_pending_virtual_indent = nil
    trim_cell_spacing(args.buf)
    index.on_text_changed(args.buf)
    actions.clamp_cursor_to_cell_left(args.buf)
    scheduler.request_render(args.buf, { immediate = true })
  end,
})

vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
  callback = function(args)
    overlay.disable(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "BufWipeout" }, {
  callback = function(args)
    scheduler.cancel(args.buf)
    exec.stop_session(args.buf)
    output.clear_all(args.buf)
  end,
})

set_default_keymaps(0)
