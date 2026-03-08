local M = {}

M.STATES = {
  idle = true,
  running = true,
  interrupting = true,
  restarting = true,
  error = true,
  stopped = true,
}

local ALLOWED = {
  idle = { running = true, interrupting = true, restarting = true, stopped = true, error = true },
  running = { idle = true, interrupting = true, restarting = true, error = true, stopped = true },
  interrupting = { idle = true, restarting = true, error = true, stopped = true },
  restarting = { idle = true, error = true, stopped = true },
  error = { idle = true, restarting = true, stopped = true },
  stopped = { idle = true, restarting = true, error = true },
}

local state_by_buf = {}

local function resolve_bufnr(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function now_ms()
  return math.floor(vim.loop.hrtime() / 1e6)
end

local function ensure_state(bufnr)
  local state = state_by_buf[bufnr]
  if state then
    return state
  end
  state = {
    state = "stopped",
    reason = nil,
    paused = false,
    updated_at = now_ms(),
  }
  state_by_buf[bufnr] = state
  return state
end

function M.get(bufnr)
  bufnr = resolve_bufnr(bufnr)
  local current = ensure_state(bufnr)
  return {
    state = current.state,
    reason = current.reason,
    paused = current.paused == true,
    updated_at = current.updated_at,
  }
end

function M.get_name(bufnr)
  return M.get(bufnr).state
end

function M.transition(bufnr, next_state, opts)
  bufnr = resolve_bufnr(bufnr)
  opts = opts or {}
  if not M.STATES[next_state] then
    return nil, "invalid session state: " .. tostring(next_state)
  end

  local current = ensure_state(bufnr)
  if current.state == next_state then
    current.reason = opts.reason
    if opts.paused ~= nil then
      current.paused = opts.paused == true
    end
    current.updated_at = now_ms()
    return true
  end

  if not opts.force then
    local allowed = ALLOWED[current.state] or {}
    if not allowed[next_state] then
      return nil, string.format("invalid session transition: %s -> %s", tostring(current.state), tostring(next_state))
    end
  end

  current.state = next_state
  current.reason = opts.reason
  if opts.paused ~= nil then
    current.paused = opts.paused == true
  end
  current.updated_at = now_ms()
  return true
end

function M.reset(bufnr, opts)
  bufnr = resolve_bufnr(bufnr)
  opts = opts or {}
  state_by_buf[bufnr] = {
    state = opts.state or "stopped",
    reason = opts.reason,
    paused = opts.paused == true,
    updated_at = now_ms(),
  }
  return true
end

function M.set_paused(bufnr, paused, opts)
  bufnr = resolve_bufnr(bufnr)
  opts = opts or {}
  local current = ensure_state(bufnr)
  current.paused = paused == true
  current.updated_at = now_ms()
  if opts.reason then
    current.reason = opts.reason
  end
  return true
end

function M.is_paused(bufnr)
  return M.get(bufnr).paused == true
end

function M.clear(bufnr)
  bufnr = resolve_bufnr(bufnr)
  state_by_buf[bufnr] = nil
end

return M
