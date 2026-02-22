local cells = require("neo_notebooks.cells")
local output = require("neo_notebooks.output")
local exec = require("neo_notebooks.exec")

local M = {}

function M.duplicate_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1

  local cell = cells.get_cell_at_line(bufnr, line)
  if cell.id then
    local index = require("neo_notebooks.index")
    local entry = index.get_by_id(bufnr, cell.id)
    if entry then
      cell.start = entry.start
      cell.finish = entry.finish
    end
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.finish + 1, false)
  local insert_at = cell.finish + 1

  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, lines)
  local index = require("neo_notebooks.index")
  index.rebuild(bufnr)
  local new_start = insert_at
  vim.api.nvim_win_set_cursor(0, { new_start + 2, 0 })
  vim.cmd("startinsert")
end

function M.split_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1

  local cell = cells.get_cell_at_line(bufnr, line)
  if cell.id then
    local index = require("neo_notebooks.index")
    local entry = index.get_by_id(bufnr, cell.id)
    if entry then
      cell.start = entry.start
      cell.finish = entry.finish
    end
  end
  if line <= cell.start then
    vim.notify("Place cursor inside the cell body to split", vim.log.levels.WARN)
    return
  end

  local marker = "# %% [" .. cell.type .. "]"
  vim.api.nvim_buf_set_lines(bufnr, line, line, false, { marker })
  if cell.id then
    output.clear_by_id(bufnr, cell.id)
  end
  local index = require("neo_notebooks.index")
  index.rebuild(bufnr)
  vim.api.nvim_win_set_cursor(0, { line + 2, 0 })
  vim.cmd("startinsert")
end

function M.clear_output(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if cell.id then
    local index = require("neo_notebooks.index")
    local entry = index.get_by_id(bufnr, cell.id)
    if entry then
      cell.start = entry.start
    end
  end
  output.clear_cell(bufnr, cell.start)
end

function M.clear_all_output(bufnr)
  bufnr = bufnr or 0
  output.clear_all(bufnr)
end

function M.delete_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if cell.id then
    local index = require("neo_notebooks.index")
    local entry = index.get_by_id(bufnr, cell.id)
    if entry then
      cell.start = entry.start
      cell.finish = entry.finish
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, cell.start, cell.finish + 1, false, {})
  local index = require("neo_notebooks.index")
  index.rebuild(bufnr)
  vim.api.nvim_win_set_cursor(0, { math.max(1, cell.start + 1), 0 })
  vim.cmd("startinsert")
end

function M.yank_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  if cell.id then
    local index = require("neo_notebooks.index")
    local entry = index.get_by_id(bufnr, cell.id)
    if entry then
      cell.start = entry.start
      cell.finish = entry.finish
    end
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start, cell.finish + 1, false)
  vim.fn.setreg("\"", lines)
  vim.notify("NeoNotebook: cell yanked", vim.log.levels.INFO)
end

local function move_once(bufnr, direction)
  local index = require("neo_notebooks.index")
  local state = index.rebuild(bufnr)
  local list = state.list
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local idx = nil
  for i, cell in ipairs(list) do
    if line >= cell.start and line <= cell.finish then
      idx = i
      break
    end
  end
  if not idx then
    return
  end

  if direction < 0 and idx == 1 then
    return
  end
  if direction > 0 and idx == #list then
    return
  end

  local current = list[idx]
  local swap = list[idx + direction]
  local id = current.id
  local cell_type = current.type
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, current.start, current.finish + 1, false)
  local current_len = current.finish - current.start + 1

  vim.api.nvim_buf_set_lines(bufnr, current.start, current.finish + 1, false, {})
  local insert_at = direction < 0 and swap.start or (swap.finish - current_len + 1)
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, current_lines)
  if id then
    vim.api.nvim_buf_set_extmark(bufnr, index.ns, insert_at, 0, { id = id })
  end
  vim.api.nvim_win_set_cursor(0, { insert_at + 2, 0 })
  index.rebuild(bufnr)
  if id and cell_type == "code" then
    output.clear_by_id(bufnr, id)
    exec.run_cell(bufnr, insert_at + 1, {
      on_output = function(lines, cell_id)
        output.show_inline(bufnr, {
          id = cell_id or id,
          start = insert_at,
          finish = insert_at + current_len - 1,
          type = cell_type,
        }, lines)
      end,
      cell_id = id,
    })
  end
end

function M.move_cell_up(bufnr, line, count)
  bufnr = bufnr or 0
  count = count or vim.v.count1
  for _ = 1, count do
    move_once(bufnr, -1)
  end
end

function M.move_cell_down(bufnr, line, count)
  bufnr = bufnr or 0
  count = count or vim.v.count1
  for _ = 1, count do
    move_once(bufnr, 1)
  end
end

function M.move_cell_top(bufnr)
  bufnr = bufnr or 0
  local index = require("neo_notebooks.index")
  local state = index.rebuild(bufnr)
  local list = state.list
  if #list == 0 then
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local idx = nil
  for i, cell in ipairs(list) do
    if line >= cell.start and line <= cell.finish then
      idx = i
      break
    end
  end
  if not idx or idx == 1 then
    return
  end
  local current = list[idx]
  local id = current.id
  local cell_type = current.type
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, current.start, current.finish + 1, false)
  vim.api.nvim_buf_set_lines(bufnr, current.start, current.finish + 1, false, {})
  local insert_at = list[1].start
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, current_lines)
  if id then
    vim.api.nvim_buf_set_extmark(bufnr, index.ns, insert_at, 0, { id = id })
  end
  vim.api.nvim_win_set_cursor(0, { insert_at + 2, 0 })
  index.rebuild(bufnr)
  if id and cell_type == "code" then
    output.clear_by_id(bufnr, id)
    exec.run_cell(bufnr, insert_at + 1, {
      on_output = function(lines, cell_id)
        output.show_inline(bufnr, {
          id = cell_id or id,
          start = insert_at,
          finish = insert_at + #current_lines - 1,
          type = cell_type,
        }, lines)
      end,
      cell_id = id,
    })
  end
end

function M.move_cell_bottom(bufnr)
  bufnr = bufnr or 0
  local index = require("neo_notebooks.index")
  local state = index.rebuild(bufnr)
  local list = state.list
  if #list == 0 then
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local idx = nil
  for i, cell in ipairs(list) do
    if line >= cell.start and line <= cell.finish then
      idx = i
      break
    end
  end
  if not idx or idx == #list then
    return
  end
  local current = list[idx]
  local id = current.id
  local cell_type = current.type
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, current.start, current.finish + 1, false)
  vim.api.nvim_buf_set_lines(bufnr, current.start, current.finish + 1, false, {})
  local insert_at = list[#list].finish + 1
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, current_lines)
  if id then
    vim.api.nvim_buf_set_extmark(bufnr, index.ns, insert_at, 0, { id = id })
  end
  vim.api.nvim_win_set_cursor(0, { insert_at + 2, 0 })
  index.rebuild(bufnr)
  if id and cell_type == "code" then
    output.clear_by_id(bufnr, id)
    exec.run_cell(bufnr, insert_at + 1, {
      on_output = function(lines, cell_id)
        output.show_inline(bufnr, {
          id = cell_id or id,
          start = insert_at,
          finish = insert_at + #current_lines - 1,
          type = cell_type,
        }, lines)
      end,
      cell_id = id,
    })
  end
end

function M.toggle_output_mode()
  local nb = require("neo_notebooks")
  if nb.config.output == "inline" then
    nb.config.output = "float"
    vim.notify("NeoNotebook: output mode = float", vim.log.levels.INFO)
  else
    nb.config.output = "inline"
    vim.notify("NeoNotebook: output mode = inline", vim.log.levels.INFO)
  end
end

function M.select_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  local start = math.min(cell.finish, cell.start + 1)
  local finish = math.max(start, cell.finish)
  vim.api.nvim_win_set_cursor(0, { start + 1, 0 })
  vim.cmd("normal! V")
  vim.api.nvim_win_set_cursor(0, { finish + 1, 0 })
end

function M.toggle_auto_render()
  local nb = require("neo_notebooks")
  nb.config.auto_render = not nb.config.auto_render
  vim.notify(string.format("NeoNotebook: auto_render = %s", tostring(nb.config.auto_render)), vim.log.levels.INFO)
end

function M.fold_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)

  vim.api.nvim_set_option_value("foldmethod", "manual", { win = 0 })
  vim.api.nvim_set_option_value("foldenable", true, { win = 0 })
  vim.cmd(string.format("%d,%dfold", cell.start + 1, cell.finish + 1))
end

function M.unfold_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  vim.cmd(string.format("%d,%dfoldopen", cell.start + 1, cell.finish + 1))
end

function M.toggle_fold_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  local cell = cells.get_cell_at_line(bufnr, line)
  local level = vim.fn.foldlevel(cell.start + 1)
  if level > 0 and vim.fn.foldclosed(cell.start + 1) ~= -1 then
    M.unfold_cell(bufnr, line)
  else
    M.fold_cell(bufnr, line)
  end
end

return M
