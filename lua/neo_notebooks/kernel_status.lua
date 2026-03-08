local M = {}

local function resolve_bufnr(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

function M.normalize_name(state)
  local name = state and state.state or "stopped"
  if state and state.paused then
    return "paused"
  end
  if name == "idle" then
    return "ok"
  end
  return name
end

function M.snapshot(bufnr)
  bufnr = resolve_bufnr(bufnr)
  local ok_exec, exec = pcall(require, "neo_notebooks.exec")
  if not ok_exec or not exec or type(exec.get_session_state) ~= "function" then
    return {
      name = "stopped",
      queue_len = 0,
      active = "no",
      alive = "no",
      reason = "-",
    }
  end
  local state = exec.get_session_state(bufnr) or {}
  return {
    name = M.normalize_name(state),
    queue_len = state.queue_len or 0,
    active = state.active_request and "yes" or "no",
    alive = state.alive and "yes" or "no",
    reason = state.reason or "-",
  }
end

function M.highlight(name)
  if name == "ok" then
    return "String"
  end
  if name == "running" or name == "interrupting" or name == "restarting" or name == "paused" then
    return "WarningMsg"
  end
  if name == "error" or name == "stopped" then
    return "ErrorMsg"
  end
  return "Identifier"
end

function M.format_notify(bufnr)
  local snap = M.snapshot(bufnr)
  if snap.reason and snap.reason ~= "" and snap.reason ~= "-" then
    return string.format(
      "NeoNotebook: kernel=%s queue=%d active=%s alive=%s reason=%s",
      snap.name,
      snap.queue_len,
      snap.active,
      snap.alive,
      snap.reason
    )
  end
  return string.format(
    "NeoNotebook: kernel=%s queue=%d active=%s alive=%s",
    snap.name,
    snap.queue_len,
    snap.active,
    snap.alive
  )
end

return M
