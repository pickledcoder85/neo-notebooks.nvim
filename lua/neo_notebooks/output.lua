local M = {}

M.ns = vim.api.nvim_create_namespace("neo_notebooks_output")

local function get_buf_var(bufnr, name, default)
  local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, name)
  if ok then
    return value
  end
  vim.api.nvim_buf_set_var(bufnr, name, default)
  return default
end

local function set_buf_var(bufnr, name, value)
  vim.api.nvim_buf_set_var(bufnr, name, value)
end

local function get_store(bufnr)
  return get_buf_var(bufnr, "neo_notebooks_output_store", {})
end

local function format_duration(duration_ms)
  if type(duration_ms) ~= "number" then
    return nil
  end
  local seconds = duration_ms / 1000
  if seconds < 1 then
    return string.format("%.0fms", duration_ms)
  end
  if seconds < 10 then
    return string.format("%.2fs", seconds)
  end
  if seconds < 60 then
    return string.format("%.1fs", seconds)
  end
  local minutes = math.floor(seconds / 60)
  local rem = seconds - (minutes * 60)
  return string.format("%dm%.0fs", minutes, rem)
end

local function with_timing(lines, duration_ms)
  local timing = format_duration(duration_ms)
  if not timing then
    return lines
  end
  local label = "[" .. timing .. "]"
  local config = require("neo_notebooks").config
  local win_width = vim.api.nvim_win_get_width(0)
  local ratio = config.cell_width_ratio or 0.9
  local width = math.floor(win_width * ratio)
  width = math.max(config.cell_min_width or 60, width)
  width = math.min(config.cell_max_width or win_width, width)
  width = math.min(width, win_width)
  width = math.max(10, width)
  local inner_width = math.max(0, width - 2)
  local label_width = vim.fn.strdisplaywidth(label)
  local left_pad = math.max(0, inner_width - label_width)
  local timing_line = string.rep(" ", left_pad) .. label
  local merged = { timing_line }
  for _, line in ipairs(lines) do
    table.insert(merged, line)
  end
  return merged
end

local function get_timing_store(bufnr)
  return get_buf_var(bufnr, "neo_notebooks_output_timing", {})
end

local function set_timing_store(bufnr, store)
  set_buf_var(bufnr, "neo_notebooks_output_timing", store)
end

function M.clear_cell(bufnr, cell_start)
  bufnr = bufnr or 0
  local index = require("neo_notebooks.index")
  local entry = index.find_cell(bufnr, cell_start)
  if entry and entry.id then
    M.clear_by_id(bufnr, entry.id)
  end
end

function M.clear_all(bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  set_buf_var(bufnr, "neo_notebooks_output_store", {})
  set_buf_var(bufnr, "neo_notebooks_output_timing", {})
end

function M.clear_by_id(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return
  end
  local store = get_store(bufnr)
  store[cell_id] = nil
  set_buf_var(bufnr, "neo_notebooks_output_store", store)
  local timing_store = get_timing_store(bufnr)
  timing_store[cell_id] = nil
  set_timing_store(bufnr, timing_store)
  local render = require("neo_notebooks.render")
  render.render_cells(bufnr, { cell_id })
end

function M.get_lines(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return nil
  end
  local store = get_store(bufnr)
  local entry = store[cell_id]
  if entry then
    return entry.lines
  end
  return nil
end

function M.get_entry(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return nil
  end
  local store = get_store(bufnr)
  return store[cell_id]
end

function M.set_timing(bufnr, cell_id, duration_ms)
  bufnr = bufnr or 0
  if not cell_id then
    return
  end
  local store = get_timing_store(bufnr)
  store[cell_id] = duration_ms
  set_timing_store(bufnr, store)
end

function M.get_timing(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return nil
  end
  local store = get_timing_store(bufnr)
  return store[cell_id]
end

function M.has_ansi(lines)
  if not lines then
    return false, 0
  end
  local count = 0
  for _, line in ipairs(lines) do
    local _, n = line:gsub("\27%[[0-9;]*m", "")
    if n > 0 then
      count = count + n
    end
  end
  return count > 0, count
end

function M.show_inline(bufnr, cell, lines, opts)
  if vim.g.neo_notebooks_debug_output then
    vim.notify("show_inline called: " .. tostring(#lines) .. " lines (buf " .. tostring(bufnr) .. ")", vim.log.levels.INFO)
  end
  bufnr = bufnr or 0
  if not lines or #lines == 0 then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return
  end

  if not cell.id then
    local index = require("neo_notebooks.index")
    local state = index.get(bufnr)
    for _, entry in ipairs(state.list) do
      if entry.start == cell.start then
        cell.id = entry.id
        break
      end
    end
  end

  if not cell.id then
    local index = require("neo_notebooks.index")
    local state = index.get(bufnr)
    for _, entry in ipairs(state.list) do
      if entry.start == cell.start and entry.finish == cell.finish then
        cell.id = entry.id
        break
      end
    end
    if not cell.id then
      local entry = index.find_cell(bufnr, cell.start)
      if entry then
        cell.id = entry.id
      end
    end
  end

  if not cell.id then
    if vim.g.neo_notebooks_debug_output then
      vim.notify("show_inline missing cell id; skipping render", vim.log.levels.WARN)
    end
    return
  end

  if cell.id then
    local store = get_store(bufnr)
    local existing = store[cell.id]
    local existing_lines = existing and existing.lines or nil
    opts = opts or {}
    local render_lines = lines
    if opts.duration_ms then
      render_lines = with_timing(lines, opts.duration_ms)
    end
    if vim.deep_equal(existing_lines, render_lines) then
      if opts.duration_ms then
        M.set_timing(bufnr, cell.id, opts.duration_ms)
        if existing then
          existing.duration_ms = opts.duration_ms
          store[cell.id] = existing
          set_buf_var(bufnr, "neo_notebooks_output_store", store)
        end
        local render = require("neo_notebooks.render")
        render.render_cells(bufnr, { cell.id })
      end
      if vim.g.neo_notebooks_debug_output then
        vim.notify("show_inline skipped (same output)", vim.log.levels.INFO)
      end
      return
    end
    store[cell.id] = {
      lines = render_lines,
      len = #render_lines,
      duration_ms = opts.duration_ms,
      executing = opts.executing == true,
    }
    set_buf_var(bufnr, "neo_notebooks_output_store", store)
    if opts.duration_ms then
      M.set_timing(bufnr, cell.id, opts.duration_ms)
    end
    if vim.g.neo_notebooks_debug_output then
      vim.notify("show_inline stored output for cell_id " .. tostring(cell.id), vim.log.levels.INFO)
    end
  end

  if vim.g.neo_notebooks_debug_output then
    vim.notify("show_inline render_outputs", vim.log.levels.INFO)
  end
  local render = require("neo_notebooks.render")
  render.render_cells(bufnr, { cell.id })
end

function M.render_block(bufnr, cell, lines)
  local config = require("neo_notebooks").config
  local win_width = vim.api.nvim_win_get_width(0)
  local ratio = config.cell_width_ratio or 0.9
  local width = math.floor(win_width * ratio)
  width = math.max(config.cell_min_width or 60, width)
  width = math.min(config.cell_max_width or win_width, width)
  width = math.min(width, win_width)
  width = math.max(10, width)
  local pad = math.max(0, math.floor((win_width - width) / 2))

  local function border(left, right)
    if width < 2 then
      return left .. right
    end
    return string.rep(" ", pad) .. left .. string.rep("─", width - 2) .. right
  end

  local virt_lines = {}
  table.insert(virt_lines, { { border("╭", "╮"), "NeoNotebookOutput" } })
  for _, line in ipairs(lines) do
    local padded = string.rep(" ", pad + 1) .. line
    table.insert(virt_lines, { { padded, "NeoNotebookOutput" } })
  end
  table.insert(virt_lines, { { border("╰", "╯"), "NeoNotebookOutput" } })

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local target = math.min(math.max(0, cell.finish), line_count - 1)
  local id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, target, 0, {
    virt_lines = virt_lines,
    priority = 200,
  })
  return id
end

function M.render_outputs(bufnr)
  bufnr = bufnr or 0
  if vim.g.neo_notebooks_debug_output then
    vim.notify("render_outputs called", vim.log.levels.INFO)
  end
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  local render = require("neo_notebooks.render")
  render.render(bufnr)
end

return M
