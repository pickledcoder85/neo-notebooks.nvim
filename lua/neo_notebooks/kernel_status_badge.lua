local M = {}

M.ns = vim.api.nvim_create_namespace("neo_notebooks_kernel_status_badge")

local function resolve_bufnr(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function state_hl(name)
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

function M.clear(bufnr)
  bufnr = resolve_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
end

function M.refresh(bufnr)
  bufnr = resolve_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local nb = require("neo_notebooks")
  if not nb.config.kernel_status_virtual then
    M.clear(bufnr)
    return
  end
  if not nb.is_notebook_buf(bufnr) then
    M.clear(bufnr)
    return
  end
  local state = nb.kernel_status(bufnr)
  local label = " kernel:" .. tostring(state) .. " "
  M.clear(bufnr)
  vim.api.nvim_buf_set_extmark(bufnr, M.ns, 0, 0, {
    virt_text = { { label, state_hl(state) } },
    virt_text_pos = "right_align",
    hl_mode = "combine",
    priority = 220,
  })
end

return M
