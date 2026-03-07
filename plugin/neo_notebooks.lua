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
local snake = require("neo_notebooks.snake")

local set_default_keymaps
local set_python_filetype
local set_snake_keymaps
local clear_snake_keymaps

set_python_filetype = function(bufnr)
  bufnr = bufnr or 0
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  if ft == "python" then
    return
  end
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("setfiletype python")
  end)
end

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

local function is_notebook_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return false
  end
  if name:match("%.ipynb$") or name:match("%.nn$") then
    return true
  end
  return false
end

local function should_enable(bufnr)
  bufnr = bufnr or 0
  if not is_notebook_path(bufnr) and not (vim.b[bufnr] and (vim.b[bufnr].neo_notebooks_enabled or vim.b[bufnr].neo_notebooks_is_ipynb)) then
    return false
  end
  if not has_filetype(bufnr) then
    return false
  end
  if nb.config.require_markers then
    return cells.has_markers(bufnr)
  end
  return true
end

local function ensure_initial_markdown_cell(bufnr)
  if not nb.config.auto_insert_first_cell then
    return
  end
  if not is_notebook_path(bufnr) and not (vim.b[bufnr] and vim.b[bufnr].neo_notebooks_is_ipynb) then
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

local function reset_undo_baseline(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local prev = vim.api.nvim_get_option_value("undolevels", { buf = bufnr })
  vim.api.nvim_set_option_value("undolevels", -1, { buf = bufnr })
  vim.api.nvim_set_option_value("undolevels", prev, { buf = bufnr })
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
      on_output = function(payload, cell_id, duration_ms)
        if vim.b[bufnr] and vim.b[bufnr].neo_notebooks_is_ipynb and cell_id and payload and payload.items then
          require("neo_notebooks.ipynb").update_cell_output(bufnr, cell_id, payload)
        end
        output.show_payload(bufnr, {
          id = cell_id or cell.id,
          start = cell.start,
          finish = cell.finish,
          type = cell.type,
        }, payload, { duration_ms = duration_ms })
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

vim.api.nvim_create_user_command("NeoNotebookOutputCollapseToggle", function()
  actions.toggle_output_collapse(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookOutputPrint", function()
  actions.print_output(0)
end, {})

vim.api.nvim_create_user_command("NeoNotebookImageClear", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if not cell or not cell.id then
    return
  end
  output.clear_images(bufnr, cell.id)
  scheduler.request_render(bufnr, { immediate = true, cell_ids = { cell.id } })
end, {})

vim.api.nvim_create_user_command("NeoNotebookImagePaneTest", function(opts)
  local path = opts.args
  if path == "" then
    path = vim.fn.getcwd() .. "/mainecoon"
  end
  path = vim.fn.fnamemodify(path, ":p")
  local pane = require("neo_notebooks.image_pane")
  pane.open()
  local ok = pane.render_file(path, "Image Test")
  if not ok then
    vim.notify("NeoNotebook: image pane test failed", vim.log.levels.WARN)
  end
end, { nargs = "?" })

vim.api.nvim_create_user_command("NeoNotebookImagePaneReset", function()
  require("neo_notebooks.image_pane").reset()
  vim.notify("NeoNotebook: image pane reset", vim.log.levels.INFO)
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
  ensure_top_padding(0)
  reset_undo_baseline(0)
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
    return
  end
  reset_undo_baseline(0)
end, { nargs = 1, complete = "file" })

vim.api.nvim_create_user_command("NeoNotebookImportJupytext", function(opts)
  local path = opts.args
  if path == "" then
    vim.notify("Provide a Jupytext .py path", vim.log.levels.WARN)
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
  local modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
  if buftype == "nofile" or not modifiable then
    vim.cmd("enew")
    bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(bufnr, path .. ".nn")
  end
  vim.b[bufnr].neo_notebooks_enabled = true
  set_python_filetype(bufnr)
  local ok, err = ipynb.import_jupytext(path, bufnr)
  if not ok then
    vim.notify(err or "Jupytext import failed", vim.log.levels.ERROR)
    return
  end
  ensure_top_padding(bufnr)
  reset_undo_baseline(bufnr)
  index.mark_dirty(bufnr)
  index.attach(bufnr)
  set_default_keymaps(bufnr)
  render_if_enabled(bufnr)
end, { nargs = 1, complete = "file" })

vim.api.nvim_create_user_command("NeoNotebookOpenJupytext", function(opts)
  local path = opts.args
  if path == "" then
    vim.notify("Provide a Jupytext .py path", vim.log.levels.WARN)
    return
  end
  local ok, err, bufnr = ipynb.open_jupytext(path)
  if not ok then
    vim.notify(err or "Jupytext open failed", vim.log.levels.ERROR)
    return
  end
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.b[bufnr].neo_notebooks_enabled = true
  set_python_filetype(bufnr)
  ensure_top_padding(bufnr)
  reset_undo_baseline(bufnr)
  index.mark_dirty(bufnr)
  index.attach(bufnr)
  set_default_keymaps(bufnr)
  render_if_enabled(bufnr)
end, { nargs = 1, complete = "file" })

vim.api.nvim_create_user_command("NeoNotebookSnakeCell", function()
  local bufnr = vim.api.nvim_get_current_buf()
  if not should_enable(bufnr) then
    vim.notify("NeoNotebook: snake mode requires a notebook buffer", vim.log.levels.WARN)
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local insert_line = cells.insert_cell_below(bufnr, line, "code")
  local state = index.rebuild(bufnr)
  local entry = nil
  for _, cell in ipairs(state.list or {}) do
    if cell.start == insert_line and cell.type == "code" then
      entry = cell
      break
    end
  end
  if not entry then
    entry = cells.get_cell_at_line(bufnr, insert_line)
  end
  if not entry or not entry.id then
    vim.notify("NeoNotebook: failed to create snake cell", vim.log.levels.ERROR)
    return
  end
  local ok, err = snake.start(bufnr, entry.id, {
    on_exit = function()
      clear_snake_keymaps(bufnr)
      set_default_keymaps(bufnr)
      render_if_enabled(bufnr)
    end,
  })
  if not ok then
    vim.notify("NeoNotebook: " .. (err or "failed to start snake mode"), vim.log.levels.ERROR)
    return
  end
  set_snake_keymaps(bufnr)
  vim.api.nvim_win_set_cursor(0, { entry.start + 2, 0 })
  render_if_enabled(bufnr)
end, {})

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

vim.api.nvim_create_user_command("PadDebug", function()
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local cfg = require("neo_notebooks").config
  local win = vim.api.nvim_win_get_width(0)
  local width = math.floor(win * (cfg.cell_width_ratio or 0.9))
  width = math.max(cfg.cell_min_width or 60, width)
  width = math.min(cfg.cell_max_width or win, width)
  width = math.min(width, win)
  local pad = math.max(0, math.floor((win - width) / 2))
  local text = vim.api.nvim_get_current_line():gsub(" ", "·")
  vim.notify(string.format("PadDebug: pad=%d col=%d line=%s", pad, vim.api.nvim_win_get_cursor(0)[2], text), vim.log.levels.INFO)
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

local keymaps_api = require("neo_notebooks.entrypoint.keymaps").new({
  nb = nb,
  cells = cells,
  markdown = markdown,
  output = output,
  overlay = overlay,
  navigation = navigation,
  actions = actions,
  run_all = run_all,
  session = session,
  stats = stats,
  run_subset = run_subset,
  help = help,
  editor = editor,
  scheduler = scheduler,
  snake = snake,
  should_enable = should_enable,
  render_if_enabled = render_if_enabled,
})

clear_snake_keymaps = keymaps_api.clear_snake_keymaps
set_snake_keymaps = keymaps_api.set_snake_keymaps
set_default_keymaps = keymaps_api.set_default_keymaps

nb._on_setup = function()
  set_default_keymaps(0)
end

require("neo_notebooks.entrypoint.lifecycle").register({
  nb = nb,
  cells = cells,
  render = render,
  output = output,
  overlay = overlay,
  actions = actions,
  ipynb = ipynb,
  index = index,
  scheduler = scheduler,
  exec = exec,
  should_enable = should_enable,
  set_default_keymaps = set_default_keymaps,
  set_python_filetype = set_python_filetype,
  render_if_enabled = render_if_enabled,
  ensure_initial_markdown_cell = ensure_initial_markdown_cell,
  ensure_top_padding = ensure_top_padding,
  trim_cell_spacing = trim_cell_spacing,
  update_completion = update_completion,
  update_textwidth = update_textwidth,
  reset_undo_baseline = reset_undo_baseline,
})

set_default_keymaps(0)
