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

print("All tests passed")
vim.cmd("qa!")
