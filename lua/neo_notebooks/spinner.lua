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
    extmark = nil,
    timer = vim.loop.new_timer(),
  }
  timers[key(bufnr, cell_id)] = entry

  local frame = 1
  local function tick()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      M.stop(bufnr, cell_id)
      return
    end
    if entry.extmark then
      pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, entry.extmark)
      entry.extmark = nil
    end
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local target = get_cell_line(bufnr, cell_id, entry.line)
    target = math.min(math.max(target, 0), math.max(0, line_count - 1))
    entry.extmark = vim.api.nvim_buf_set_extmark(bufnr, M.ns, target, 0, {
      sign_text = frames[frame],
      sign_hl_group = "NeoNotebookSpinner",
      priority = 200,
    })
    frame = frame % #frames + 1
  end

  tick()
  entry.timer:start(120, 120, vim.schedule_wrap(tick))
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
  if vim.api.nvim_buf_is_valid(bufnr) and entry.extmark then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, entry.extmark)
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
