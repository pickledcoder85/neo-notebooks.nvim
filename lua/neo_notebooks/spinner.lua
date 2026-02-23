local M = {}
M.ns = vim.api.nvim_create_namespace("neo_notebooks_spinner")

local frames = { "|", "/", "-", "\\" }
local timers = {}

local function key(bufnr, cell_id)
  return tostring(bufnr) .. ":" .. tostring(cell_id)
end

local function get_cell_line(bufnr, cell_id, fallback)
  local index = require("neo_notebooks.index")
  local cell = index.get_by_id(bufnr, cell_id)
  if cell then
    return cell.start
  end
  return fallback or 0
end

local function leading_spaces(text)
  if type(text) ~= "string" then
    return nil
  end
  local _, e = text:find("^%s*")
  if not e then
    return 0
  end
  return e
end

local function get_left_col_from_render(bufnr, line)
  local ok, render = pcall(require, "neo_notebooks.render")
  if not ok or not render or not render.ns then
    return nil
  end
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, render.ns, { line, 0 }, { line, -1 }, { details = true })
  for _, mark in ipairs(marks) do
    local details = mark[4]
    if details and details.virt_lines_above and details.virt_lines and details.virt_lines[1] and details.virt_lines[1][1] then
      local chunk = details.virt_lines[1][1]
      local text = chunk and chunk[1]
      local spaces = leading_spaces(text)
      if spaces then
        return math.max(0, spaces)
      end
    end
  end
  return nil
end

local function get_spinner_col(bufnr, cell_id, target_line)
  local from_render = get_left_col_from_render(bufnr, target_line or 0)
  if from_render ~= nil then
    if from_render <= 0 then
      return 0
    end
    return from_render - 1
  end
  local index = require("neo_notebooks.index")
  local cell = index.get_by_id(bufnr, cell_id)
  if not cell or not cell.layout then
    local win = vim.fn.bufwinid(bufnr)
    if not win or win == -1 then
      return 0
    end
    local cfg = require("neo_notebooks").config
    local win_width = vim.api.nvim_win_get_width(win)
    local ratio = cfg.cell_width_ratio or 0.9
    local width = math.floor(win_width * ratio)
    width = math.max(cfg.cell_min_width or 60, width)
    width = math.min(cfg.cell_max_width or win_width, width)
    width = math.min(width, win_width)
    width = math.max(10, width)
    local pad = math.max(0, math.floor((win_width - width) / 2))
    if pad == 0 then
      return 0
    end
    return pad - 1
  end
  local left_col = cell.layout.left_col or 0
  if left_col <= 0 then
    return 0
  end
  return left_col - 1
end

function M.start(bufnr, cell_id, line)
  bufnr = bufnr or 0
  if not cell_id then
    return
  end
  M.stop(bufnr, cell_id)
  local entry = {
    bufnr = bufnr,
    cell_id = cell_id,
    line = line or 0,
    virt_extmark = nil,
    timer = vim.loop.new_timer(),
  }
  timers[key(bufnr, cell_id)] = entry

  local frame = 1
  local function tick()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      M.stop(bufnr, cell_id)
      return
    end
    if entry.virt_extmark then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, entry.virt_extmark)
      entry.virt_extmark = nil
    end
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local target = get_cell_line(bufnr, cell_id, entry.line)
    target = math.min(math.max(target, 0), math.max(0, line_count - 1))
    local col = get_spinner_col(bufnr, cell_id, target)
    entry.virt_extmark = vim.api.nvim_buf_set_extmark(bufnr, M.ns, target, 0, {
      virt_text = { { frames[frame], "NeoNotebookSpinner" } },
      virt_text_pos = "overlay",
      virt_text_win_col = col,
      priority = 320,
    })
    frame = frame % #frames + 1
  end

  tick()
  entry.timer:start(90, 90, vim.schedule_wrap(tick))
end

function M.stop(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return
  end
  local entry = timers[key(bufnr, cell_id)]
  if not entry then
    return
  end
  if entry.timer then
    entry.timer:stop()
    entry.timer:close()
  end
  if vim.api.nvim_buf_is_valid(bufnr) then
    if entry.virt_extmark then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, entry.virt_extmark)
    end
  end
  timers[key(bufnr, cell_id)] = nil
end

function M.stop_all(bufnr)
  bufnr = bufnr or 0
  local keys = {}
  for k, entry in pairs(timers) do
    if entry.bufnr == bufnr then
      table.insert(keys, k)
    end
  end
  for _, k in ipairs(keys) do
    local entry = timers[k]
    if entry then
      M.stop(entry.bufnr, entry.cell_id)
    end
  end
end

return M
