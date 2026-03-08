local M = {}

local state_by_buf = {}

local function resolve_bufnr(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function status_lines(bufnr)
  local exec = require("neo_notebooks.exec")
  local state = exec.get_session_state(bufnr)
  local name = state and state.state or "stopped"
  if state and state.paused then
    name = "paused"
  elseif name == "idle" then
    name = "ok"
  end
  local queue_len = state and state.queue_len or 0
  local active = state and state.active_request and "yes" or "no"
  local alive = state and state.alive and "yes" or "no"
  return {
    "NeoNotebook Kernel",
    string.format("state:  %s", name),
    string.format("queue:  %d", queue_len),
    string.format("active: %s", active),
    string.format("alive:  %s", alive),
    "",
    "<leader>kk toggle",
  }
end

local function panel_col(width)
  return math.max(1, vim.o.columns - width - 2)
end

local function close_state(bufnr)
  local st = state_by_buf[bufnr]
  if not st then
    return
  end
  if st.timer then
    st.timer:stop()
    st.timer:close()
    st.timer = nil
  end
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    pcall(vim.api.nvim_win_close, st.win, true)
  end
  if st.buf and vim.api.nvim_buf_is_valid(st.buf) then
    pcall(vim.api.nvim_buf_delete, st.buf, { force = true })
  end
  state_by_buf[bufnr] = nil
end

local function render_state(bufnr)
  local st = state_by_buf[bufnr]
  if not st or not (st.buf and vim.api.nvim_buf_is_valid(st.buf)) then
    close_state(bufnr)
    return false
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    close_state(bufnr)
    return false
  end
  local lines = status_lines(bufnr)
  vim.api.nvim_set_option_value("modifiable", true, { buf = st.buf })
  vim.api.nvim_buf_set_lines(st.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = st.buf })
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    local cfg = vim.api.nvim_win_get_config(st.win)
    cfg.col = panel_col(st.width)
    vim.api.nvim_win_set_config(st.win, cfg)
  end
  return true
end

function M.open(bufnr)
  bufnr = resolve_bufnr(bufnr)
  if state_by_buf[bufnr] then
    return true
  end

  local width = 30
  local height = 9
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = 1,
    col = panel_col(width),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
  })

  state_by_buf[bufnr] = {
    buf = buf,
    win = win,
    width = width,
    height = height,
  }
  render_state(bufnr)

  local timer = vim.loop.new_timer()
  state_by_buf[bufnr].timer = timer
  timer:start(0, 500, vim.schedule_wrap(function()
    render_state(bufnr)
  end))
  return true
end

function M.close(bufnr)
  bufnr = resolve_bufnr(bufnr)
  if not state_by_buf[bufnr] then
    return false
  end
  close_state(bufnr)
  return true
end

function M.toggle(bufnr)
  bufnr = resolve_bufnr(bufnr)
  if state_by_buf[bufnr] then
    M.close(bufnr)
    return false
  end
  M.open(bufnr)
  return true
end

function M.is_open(bufnr)
  bufnr = resolve_bufnr(bufnr)
  local st = state_by_buf[bufnr]
  if not st then
    return false
  end
  return st.win and vim.api.nvim_win_is_valid(st.win) or false
end

return M
