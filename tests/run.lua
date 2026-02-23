local function add_rtp(path)
  vim.opt.rtp:append(path)
end

add_rtp(vim.fn.getcwd())
vim.opt.shadafile = "NONE"

local function ok(cond, msg)
  if not cond then
    error(msg or "assertion failed")
  end
end

local function eq(a, b, msg)
  if a ~= b then
    error((msg or "assertion failed") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
  end
end

local function new_buf(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function with_buf(lines, fn)
  local buf = new_buf(lines)
  local ok_run, err = pcall(fn, buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  if not ok_run then
    error(err)
  end
end

local index = require("neo_notebooks.index")
local cells = require("neo_notebooks.cells")
local actions = require("neo_notebooks.actions")
local output = require("neo_notebooks.output")
local render = require("neo_notebooks.render")
local index_mod = require("neo_notebooks.index")
local ipynb = require("neo_notebooks.ipynb")
local nb = require("neo_notebooks")

-- Test: index build
with_buf({
  "# %% [code]",
  "print(1)",
  "",
  "# %% [markdown]",
  "# Title",
}, function(buf)
  local state = index.rebuild(buf)
  eq(#state.list, 2, "cell count")
  ok(state.list[1].id, "id set")
  ok(state.by_id[state.list[1].id], "by_id has entry")
  eq(state.list[1].type, "code", "first type")
  eq(state.list[2].type, "markdown", "second type")
end)

-- Test: stable id across rebuild after body edit
with_buf({
  "# %% [code]",
  "print(1)",
  "",
}, function(buf)
  local state = index.rebuild(buf)
  local id = state.list[1].id
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "print(2)" })
  state = index.rebuild(buf)
  eq(state.list[1].id, id, "id stable after edit")
end)

-- Test: get_cell_at_line uses index
with_buf({
  "# %% [code]",
  "print(1)",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local cell = cells.get_cell_at_line(buf, 2)
  eq(cell.start, 2, "cell lookup by line")
end)

-- Test: move cell up preserves id mapping
with_buf({
  "# %% [code]",
  "print(1)",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local first = index.get(buf).list[1].id
  local second = index.get(buf).list[2].id
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    actions.move_cell_up(buf)
  end)
  index.rebuild(buf)
  eq(index.get(buf).list[1].id, second, "move up swaps order")
  eq(index.get(buf).by_id[first].id, first, "id stays stable")
end)

-- Test: output storage uses cell id and renders without error
with_buf({
  "# %% [code]",
  "print(1)",
}, function(buf)
  local state = index.rebuild(buf)
  local cell = state.list[1]
  output.show_inline(buf, { id = cell.id, start = cell.start, finish = cell.finish, type = cell.type }, { "ok" })
  local lines = output.get_lines(buf, cell.id)
  ok(lines and #lines == 1 and lines[1] == "ok", "output stored")
  render.render(buf)
end)

-- Test: render rebuilds index after delete-like edits (prevents stale borders)
with_buf({
  "# %% [code]",
  "a = 1",
  "",
  "# %% [code]",
  "b = 2",
}, function(buf)
  nb.setup({ auto_render = false, soft_contain = false })
  index.rebuild(buf)
  render.render(buf)
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, {}) -- simulate dd in first cell body
  render.render(buf)
  local state = index.get(buf)
  eq(state.list[2].start, 2, "second cell marker shifted up after delete")
end)

-- Test: insert cell below creates new id
with_buf({
  "# %% [code]",
  "print(1)",
}, function(buf)
  index.rebuild(buf)
  vim.api.nvim_buf_call(buf, function()
    actions.split_cell(buf, 1)
  end)
  local state = index.rebuild(buf)
  eq(#state.list, 2, "split adds a cell")
  ok(state.list[1].id ~= state.list[2].id, "ids are unique")
end)

-- Test: ipynb round-trip (export then import)
with_buf({
  "# %% [code]",
  "print(1)",
  "",
  "# %% [markdown]",
  "# Title",
}, function(buf)
  local path = vim.fn.tempname() .. ".ipynb"
  local ok_export, err_export = ipynb.export_ipynb(path, buf)
  ok(ok_export, err_export or "export failed")

  local buf2 = vim.api.nvim_create_buf(false, true)
  local ok_import, err_import = ipynb.import_ipynb(path, buf2)
  ok(ok_import, err_import or "import failed")
  local state = index.rebuild(buf2)
  eq(#state.list, 2, "round-trip cell count")
  vim.api.nvim_buf_delete(buf2, { force = true })
end)

-- Test: ipynb import drops leading blank code cell before markdown
with_buf({
  "# %% [code]",
  "print(1)",
}, function(buf)
  local path = vim.fn.tempname() .. ".ipynb"
  local doc = {
    cells = {
      { cell_type = "code", metadata = {}, source = { "\n", "\n", "\n" } },
      { cell_type = "markdown", metadata = {}, source = { "# Title\n" } },
      { cell_type = "code", metadata = {}, source = { "print(2)\n" } },
    },
    metadata = { language_info = { name = "python" } },
    nbformat = 4,
    nbformat_minor = 5,
  }
  vim.fn.writefile({ vim.fn.json_encode(doc) }, path)
  local ok_import, err_import = ipynb.import_ipynb(path, buf)
  ok(ok_import, err_import or "import failed")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, 2, false)
  eq(lines[1], "# %% [markdown]", "leading blank code cell removed on import")
end)

-- Test: line insertion inside a cell shifts following cells
with_buf({
  "# %% [code]",
  "print(1)",
  "",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    actions.open_line_below(buf)
  end)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[4], "", "inserted line exists in first cell")
  eq(lines[5], "# %% [code]", "next cell marker shifts down")
end)

-- Test: normalize_spacing trims drifted trailing gaps
with_buf({
  "# %% [code]",
  "print(1)",
  "",
  "",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  actions.normalize_spacing(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[3], "", "single preserved blank before next marker")
  eq(lines[4], "# %% [code]", "next marker pulled up after trim")
end)

-- Test: insert-mode newline near cell bottom chooses contained open-line path
with_buf({
  "# %% [code]",
  "print(1)",
  "",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local res = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 2, 8 })
    res = actions.insert_newline_in_cell(buf)
  end)
  ok(type(res) == "string" and res:find("open_line_below", 1, true) ~= nil, "bottom-adjacent newline uses contained insertion")
end)

-- Test: insert-mode newline in regular body returns normal newline
with_buf({
  "# %% [code]",
  "line1",
  "line2",
  "line3",
  "",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local res = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 3, 2 })
    res = actions.insert_newline_in_cell(buf)
  end)
  eq(res, "<CR>", "regular body newline keeps default split behavior")
end)

-- Test: containment navigation keeps cursor out of marker-only cell border
with_buf({
  "# %% [code]",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local pos = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    actions.goto_cell_top(buf)
    pos = vim.api.nvim_win_get_cursor(0)
  end)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(lines[2], "", "empty body line inserted for marker-only cell")
  eq(pos[1], 2, "cursor moved to cell body line")
end)

-- Test: clamp empty-line cursor to virtual left boundary
with_buf({
  "# %% [code]",
  "",
  "# %% [code]",
}, function(buf)
  index.rebuild(buf)
  local virt = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    actions.clamp_cursor_to_cell_left(buf)
    virt = vim.fn.virtcol(".")
  end)
  ok(virt > 1, "cursor moved right to contained left boundary")
end)

-- Test: dd guard blocks marker deletion
with_buf({
  "# %% [markdown]",
  "line 1",
  "",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local keys = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    keys = actions.guard_delete_current_line(buf, 1)
  end)
  eq(keys, "", "marker-line dd is blocked")
end)

-- Test: dd guard blocks protected spacing near next marker
with_buf({
  "# %% [markdown]",
  "line 1",
  "",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local keys = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    keys = actions.guard_delete_current_line(buf, 1)
  end)
  eq(keys, "", "bottom spacing dd is blocked")
end)

-- Test: dd guard allows deletion away from protected zone
with_buf({
  "# %% [markdown]",
  "a",
  "b",
  "",
  "# %% [code]",
}, function(buf)
  index.rebuild(buf)
  local keys = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    keys = actions.guard_delete_current_line(buf, 1)
  end)
  eq(keys, "dd", "regular dd remains allowed")
end)

-- Test: x guard blocks marker mutation
with_buf({
  "# %% [markdown]",
  "line 1",
}, function(buf)
  index.rebuild(buf)
  local keys = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    keys = actions.guard_delete_char(buf)
  end)
  eq(keys, "", "x blocked on marker line")
end)

-- Test: D guard blocks marker mutation
with_buf({
  "# %% [markdown]",
  "line 1",
}, function(buf)
  index.rebuild(buf)
  local keys = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    keys = actions.guard_delete_to_eol(buf)
  end)
  eq(keys, "", "D blocked on marker line")
end)

-- Test: visual-line d guard blocks protected spacing removal
with_buf({
  "# %% [markdown]",
  "line 1",
  "",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local keys = actions.guard_visual_delete(buf, "V", 2, 2)
  eq(keys, "", "visual line delete blocked in protected zone")
end)

-- Test: visual-char d guard allows normal body edits
with_buf({
  "# %% [markdown]",
  "line 1",
}, function(buf)
  index.rebuild(buf)
  local keys = actions.guard_visual_delete(buf, "v", 1, 1)
  eq(keys, "d", "visual char delete allowed in body")
end)

-- Test: insert backspace guard blocks marker edits
with_buf({
  "# %% [markdown]",
  "line 1",
}, function(buf)
  index.rebuild(buf)
  local keys = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
    keys = actions.guard_backspace_in_insert(buf)
  end)
  eq(keys, "", "insert backspace blocked on marker")
end)

-- Test: insert backspace guard blocks merge into marker
with_buf({
  "# %% [markdown]",
  "line 1",
}, function(buf)
  index.rebuild(buf)
  local keys = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    keys = actions.guard_backspace_in_insert(buf)
  end)
  eq(keys, "", "insert backspace blocked when previous line is marker")
end)

-- Test: insert backspace guard allows normal body delete
with_buf({
  "# %% [markdown]",
  "line 1",
}, function(buf)
  index.rebuild(buf)
  local keys = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 2, 3 })
    keys = actions.guard_backspace_in_insert(buf)
  end)
  eq(keys, "<BS>", "insert backspace allowed in body text")
end)

-- Test: cursor state exposes active cell id and index
with_buf({
  "# %% [markdown]",
  "m1",
  "",
  "# %% [code]",
  "c1",
}, function(buf)
  local state = index.rebuild(buf)
  local s = actions.get_cursor_state(buf, 4, 0)
  eq(s.active_cell_id, state.list[2].id, "active cell id matches index entry")
  eq(s.active_cell_index, 2, "active cell index matches second cell")
end)

-- Test: normal-mode enter stays inside current cell near bottom
with_buf({
  "# %% [markdown]",
  "line 1",
  "",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local pos = nil
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    actions.handle_enter_normal(buf)
    pos = vim.api.nvim_win_get_cursor(0)
  end)
  ok(pos[1] < 4, "normal enter does not step into next marker")
end)

print("All tests passed")
vim.cmd("qa!")
