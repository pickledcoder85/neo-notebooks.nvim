local M = {}

local pending = {}

local function clear_entry(bufnr)
  local entry = pending[bufnr]
  if not entry then
    return
  end
  if entry.timer then
    entry.timer:stop()
    entry.timer:close()
  end
  pending[bufnr] = nil
end

local function render_now(bufnr, entry)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    clear_entry(bufnr)
    return
  end
  local nb = require("neo_notebooks")
  if not nb.config.auto_render then
    clear_entry(bufnr)
    return
  end
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    clear_entry(bufnr)
    return
  end
  local render = require("neo_notebooks.render")
  vim.api.nvim_win_call(win, function()
    if entry and entry.full == false and entry.cell_ids then
      local ids = {}
      for id in pairs(entry.cell_ids) do
        table.insert(ids, id)
      end
      render.render_cells(bufnr, ids)
    else
      render.render(bufnr)
    end
  end)
  clear_entry(bufnr)
end

function M.request_render(bufnr, opts)
  bufnr = bufnr or 0
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if opts.immediate then
    vim.schedule(function()
      local entry = nil
      if opts.cell_ids then
        local set = {}
        for _, id in ipairs(opts.cell_ids) do
          set[id] = true
        end
        entry = { full = false, cell_ids = set }
      else
        entry = { full = true }
      end
      render_now(bufnr, entry)
    end)
    return
  end

  local delay = opts.debounce_ms
  if delay == nil then
    delay = 20
  end
  delay = math.max(0, delay)

  local entry = pending[bufnr]
  if not entry then
    entry = { timer = vim.loop.new_timer() }
    pending[bufnr] = entry
  else
    entry.timer:stop()
  end
  if opts.cell_ids then
    if entry.full ~= true then
      entry.full = false
      entry.cell_ids = entry.cell_ids or {}
      for _, id in ipairs(opts.cell_ids) do
        entry.cell_ids[id] = true
      end
    end
  else
    entry.full = true
    entry.cell_ids = nil
  end

  entry.timer:start(delay, 0, vim.schedule_wrap(function()
    render_now(bufnr, entry)
  end))
end

function M.cancel(bufnr)
  bufnr = bufnr or 0
  clear_entry(bufnr)
end

return M
