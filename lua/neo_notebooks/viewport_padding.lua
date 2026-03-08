local M = {}

M.ns = vim.api.nvim_create_namespace("neo_notebooks_viewport_padding")

local function resolve_bufnr(bufnr)
  bufnr = bufnr or 0
  if bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function parse_padding()
  local nb = require("neo_notebooks")
  local cfg = nb.config.viewport_virtual_padding
  if type(cfg) == "number" then
    local n = math.max(0, math.floor(cfg))
    return n, n
  end
  if type(cfg) == "table" then
    local top = cfg.top or cfg[1] or 0
    local bottom = cfg.bottom or cfg[2] or 0
    top = math.max(0, math.floor(tonumber(top) or 0))
    bottom = math.max(0, math.floor(tonumber(bottom) or 0))
    return top, bottom
  end
  return 0, 0
end

local function blank_virt_lines(count)
  local lines = {}
  for _ = 1, count do
    lines[#lines + 1] = { { " ", "Normal" } }
  end
  return lines
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
  if not nb.is_notebook_buf(bufnr) then
    M.clear(bufnr)
    return
  end

  local top_pad, bottom_pad = parse_padding()
  if top_pad <= 0 and bottom_pad <= 0 then
    M.clear(bufnr)
    return
  end

  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    M.clear(bufnr)
    return
  end

  local top_line = vim.api.nvim_win_call(win, function()
    return vim.fn.line("w0")
  end)
  local bot_line = vim.api.nvim_win_call(win, function()
    return vim.fn.line("w$")
  end)

  local top_row = math.max(0, (top_line or 1) - 1)
  local bot_row = math.max(0, (bot_line or 1) - 1)

  M.clear(bufnr)

  if top_pad > 0 then
    if top_row > 0 then
      -- Anchor to the line just above the viewport so spacer rows render at the top edge.
      vim.api.nvim_buf_set_extmark(bufnr, M.ns, top_row - 1, 0, {
        virt_lines = blank_virt_lines(top_pad),
        priority = 150,
      })
    else
      vim.api.nvim_buf_set_extmark(bufnr, M.ns, top_row, 0, {
        virt_lines = blank_virt_lines(top_pad),
        virt_lines_above = true,
        priority = 150,
      })
    end
  end
  if bottom_pad > 0 then
    vim.api.nvim_buf_set_extmark(bufnr, M.ns, bot_row, 0, {
      virt_lines = blank_virt_lines(bottom_pad),
      priority = 150,
    })
  end
end

return M
