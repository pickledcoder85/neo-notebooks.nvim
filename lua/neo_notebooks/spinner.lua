local M = {}
M.ns = vim.api.nvim_create_namespace("neo_notebooks_spinner")

local frames = { "|", "/", "-", "\\" }
local timers = {}
local last_frames = {}

local function key(bufnr, cell_id)
  return tostring(bufnr) .. ":" .. tostring(cell_id)
end

local function rerender(bufnr, cell_id)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local ok, scheduler = pcall(require, "neo_notebooks.scheduler")
  if not ok or not scheduler then
    return
  end
  if cell_id then
    scheduler.request_render(bufnr, { debounce_ms = 16, cell_ids = { cell_id } })
  else
    scheduler.request_render(bufnr, { debounce_ms = 16 })
  end
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
    frame = frames[1],
    timer = vim.loop.new_timer(),
  }
  timers[key(bufnr, cell_id)] = entry
  last_frames[key(bufnr, cell_id)] = entry.frame

  local frame = 1
  local function tick()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      M.stop(bufnr, cell_id)
      return
    end
    entry.frame = frames[frame]
    last_frames[key(bufnr, cell_id)] = entry.frame
    rerender(bufnr, cell_id)
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
  timers[key(bufnr, cell_id)] = nil
  rerender(bufnr, cell_id)
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

function M.get_frame(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return nil
  end
  local entry = timers[key(bufnr, cell_id)]
  if not entry then
    return nil
  end
  return entry.frame
end

function M.get_frame_or_last(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return nil
  end
  local entry = timers[key(bufnr, cell_id)]
  if entry then
    return entry.frame
  end
  return last_frames[key(bufnr, cell_id)]
end

function M.is_active(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return false
  end
  return timers[key(bufnr, cell_id)] ~= nil
end

return M
