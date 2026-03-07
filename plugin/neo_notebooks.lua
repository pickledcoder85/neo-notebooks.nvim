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

require("neo_notebooks.entrypoint.commands").register({
  nb = nb,
  cells = cells,
  render = render,
  exec = exec,
  markdown = markdown,
  output = output,
  overlay = overlay,
  navigation = navigation,
  actions = actions,
  ipynb = ipynb,
  run_all = run_all,
  session = session,
  stats = stats,
  run_subset = run_subset,
  help = help,
  editor = editor,
  index = index,
  scheduler = scheduler,
  snake = snake,
  set_python_filetype = set_python_filetype,
  should_enable = should_enable,
  ensure_top_padding = ensure_top_padding,
  render_if_enabled = render_if_enabled,
  reset_undo_baseline = reset_undo_baseline,
  set_default_keymaps = set_default_keymaps,
  set_snake_keymaps = set_snake_keymaps,
  clear_snake_keymaps = clear_snake_keymaps,
})

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
