local M = {}

local function apply_index_sync(bufnr, mode)
  if mode == nil or mode == false then
    return
  end
  local index = require("neo_notebooks.index")
  if mode == "on_text_changed" then
    index.on_text_changed(bufnr)
    return
  end
  if mode == "mark_dirty" then
    index.mark_dirty(bufnr)
    return
  end
end

local function apply_render_sync(bufnr, render_opts)
  if render_opts == nil or render_opts == false then
    return
  end
  local scheduler = require("neo_notebooks.scheduler")
  scheduler.request_render(bufnr, render_opts)
end

function M.apply(bufnr, start_line, end_line, replacement, opts)
  bufnr = bufnr or 0
  opts = opts or {}
  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, replacement)
  apply_index_sync(bufnr, opts.index_sync)
  apply_render_sync(bufnr, opts.render)
end

return M
