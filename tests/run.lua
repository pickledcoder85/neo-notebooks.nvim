local function add_rtp(path)
  vim.opt.rtp:append(path)
end

add_rtp(vim.fn.getcwd())

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
local index_mod = require("neo_notebooks.index")
local ipynb = require("neo_notebooks.ipynb")

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

-- Test: output placement uses id and does not error
with_buf({
  "# %% [code]",
  "print(1)",
}, function(buf)
  local state = index.rebuild(buf)
  local cell = state.list[1]
  output.show_inline(buf, { id = cell.id, start = cell.start, finish = cell.finish, type = cell.type }, { "ok" })
  local marks = vim.api.nvim_buf_get_extmarks(buf, output.ns, 0, -1, {})
  ok(#marks > 0, "output extmark created")
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

print("All tests passed")
vim.cmd("qa!")
