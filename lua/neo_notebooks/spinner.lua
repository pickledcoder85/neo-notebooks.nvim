local M = {}
M.ns = vim.api.nvim_create_namespace("neo_notebooks_spinner")

local frames = { "|", "/", "-", "\\" }
local timers = {}
local last_frames = {}

local function resolve_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function key(bufnr, cell_id)
  bufnr = resolve_bufnr(bufnr)
  return tostring(bufnr) .. ":" .. tostring(cell_id)
end

local function rerender(bufnr, cell_id)
  bufnr = resolve_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local ok, scheduler = pcall(require, "neo_notebooks.scheduler")
  if not ok or not scheduler then
    return
  end
  if cell_id then
    scheduler.request_render(bufnr, { immediate = true, cell_ids = { cell_id } })
  else
    scheduler.request_render(bufnr, { immediate = true })
  end
end

function M.start(bufnr, cell_id, line)
  bufnr = resolve_bufnr(bufnr)
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
    local ok_out, out = pcall(require, "neo_notebooks.output")
    if ok_out and out then
      out.update_executing_line(bufnr, cell_id, entry.frame)
    end
    rerender(bufnr, cell_id)
    frame = frame % #frames + 1
  end

  tick()
  entry.timer:start(90, 90, vim.schedule_wrap(tick))
end

function M.stop(bufnr, cell_id)
  bufnr = resolve_bufnr(bufnr)
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
  bufnr = resolve_bufnr(bufnr)
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
  bufnr = resolve_bufnr(bufnr)
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
  bufnr = resolve_bufnr(bufnr)
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
  bufnr = resolve_bufnr(bufnr)
  if not cell_id then
    return false
  end
  return timers[key(bufnr, cell_id)] ~= nil
end

function M.has_frame_prefix(text)
  if not text or text == "" then
    return false
  end
  local first = text:sub(1, 1)
  local second = text:sub(2, 2)
  if second ~= " " then
    return false
  end
  for _, frame in ipairs(frames) do
    if first == frame then
      return true
    end
  end
  return false
end

return M
