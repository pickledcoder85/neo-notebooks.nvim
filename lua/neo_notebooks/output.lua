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

local function split_text_lines(text)
  local lines = {}
  if text == nil or text == "" then
    return lines
  end
  for line in text:gmatch("([^\n]*)\n?") do
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  return lines
end

local function kitty_supported()
  local config = require("neo_notebooks").config
  local mode = config.image_protocol or "auto"
  if mode == "none" then
    return false
  end
  if mode == "kitty" then
    return true
  end
  if mode == "auto" and vim.env.TMUX then
    return true
  end
  local term = (vim.env.TERM or ""):lower()
  local term_program = (vim.env.TERM_PROGRAM or ""):lower()
  if vim.env.KITTY_WINDOW_ID or vim.env.KITTY_PID then
    return true
  end
  if term:find("kitty", 1, true) or term:find("ghostty", 1, true) then
    return true
  end
  if term_program:find("ghostty", 1, true) then
    return true
  end
  return false
end

local function image_target()
  local config = require("neo_notebooks").config
  return config.image_render_target or "pane"
end

local function image_renderer()
  local config = require("neo_notebooks").config
  return config.image_renderer or "auto"
end

local function use_kitty_renderer()
  local renderer = image_renderer()
  if renderer == "kitty" then
    return true
  end
  return renderer == "auto" and kitty_supported()
end


local function target_win_width(bufnr)
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    local wins = vim.fn.win_findbuf(bufnr)
    if wins and #wins > 0 then
      win = wins[1]
    end
  end
  if win ~= -1 then
    return vim.api.nvim_win_get_width(win)
  end
  return vim.api.nvim_win_get_width(0)
end

local function output_inner_width(bufnr)
  local config = require("neo_notebooks").config
  local win_width = target_win_width(bufnr)
  local ratio = config.cell_width_ratio or 0.9
  local width = math.floor(win_width * ratio)
  width = math.max(config.cell_min_width or 60, width)
  width = math.min(config.cell_max_width or win_width, width)
  width = math.min(width, win_width)
  width = math.max(10, width)
  return math.max(1, width - 2)
end

local function target_win_height(bufnr)
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    local wins = vim.fn.win_findbuf(bufnr)
    if wins and #wins > 0 then
      win = wins[1]
    end
  end
  if win ~= -1 then
    return vim.api.nvim_win_get_height(win)
  end
  return vim.api.nvim_win_get_height(0)
end

local function image_rows_from_meta(bufnr, meta)
  if meta and meta.rows then
    return math.max(1, math.floor(meta.rows))
  end
  local inner_width = output_inner_width(bufnr)
  local config = require("neo_notebooks").config
  if config.image_size_mode == "default" then
    local fallback = config.image_default_rows or 1
    local max_rows = config.image_max_rows or math.max(5, target_win_height(bufnr) - 2)
    return math.min(math.max(1, fallback), max_rows)
  end
  if not meta or not meta.width or not meta.height then
    local fallback = config.image_default_rows or 1
    local max_rows = config.image_max_rows or math.max(5, target_win_height(bufnr) - 2)
    return math.min(math.max(1, fallback), max_rows)
  end
  local aspect = meta.height / math.max(1, meta.width)
  local rows = math.max(1, math.floor(inner_width * aspect))
  local max_rows = config.image_max_rows or math.max(5, target_win_height(bufnr) - 2)
  return math.min(rows, max_rows)
end

local function image_cols_from_meta(bufnr, meta)
  if meta and meta.cols then
    return math.max(1, math.floor(meta.cols))
  end
  local config = require("neo_notebooks").config
  if config.image_size_mode == "default" then
    return math.max(1, config.image_default_cols or output_inner_width(bufnr))
  end
  if not meta or not meta.width or not meta.height then
    return math.max(1, config.image_default_cols or output_inner_width(bufnr))
  end
  return output_inner_width(bufnr)
end

local function render_lines_for_items(bufnr, items, opts)
  local lines = {}
  local config = require("neo_notebooks").config
  local inner_width = output_inner_width(bufnr)
  local has_image = false
  local prefer_kitty = opts and opts.kitty == true
  local target = image_target()
  local pane = require("neo_notebooks.image_pane")
  local image_paths = opts and opts.image_paths or {}
  local rendered_in_pane = opts and opts.rendered_in_pane or false
  local placements = {}
  for _, item in ipairs(items or {}) do
    local kind = item.type or "text/plain"
    if kind == "text/plain" or kind == "text" then
      local text_lines = split_text_lines(item.data or "")
      for _, line in ipairs(text_lines) do
        table.insert(lines, line)
      end
    elseif kind == "image/png" then
      if prefer_kitty and target == "pane" then
        if rendered_in_pane then
          table.insert(lines, string.format("[image rendered in pane: cell %s]", tostring(opts and opts.cell_id or "?")))
          has_image = true
        elseif #image_paths > 0 then
          for _, path in ipairs(image_paths) do
            table.insert(lines, string.format("[image saved: %s]", path))
          end
          has_image = true
        else
          if (config.image_fallback or "placeholder") == "placeholder" then
            table.insert(lines, "[image rendering requires tmux pane]")
          end
        end
      elseif prefer_kitty then
        local rows = image_rows_from_meta(bufnr, item.meta or {})
        local cols = image_cols_from_meta(bufnr, item.meta or {})
        local offset = #lines + 1
        for _ = 1, rows do
          table.insert(lines, "")
        end
        table.insert(placements, { item = item, offset = offset, rows = rows, cols = cols })
        has_image = true
      else
        if (config.image_fallback or "placeholder") == "placeholder" then
          table.insert(lines, "[image/png output not supported in this terminal]")
        end
      end
    else
      table.insert(lines, string.format("[%s output omitted]", kind))
    end
  end
  if #lines == 0 then
    if has_image then
      lines = { "" }
    else
      lines = { "(no output)" }
    end
  end
  return lines, has_image, placements
end

local function with_timing(lines, duration_ms, bufnr)
  local timing = format_duration(duration_ms)
  if not timing then
    return lines
  end
  local label = "[" .. timing .. "]"
  local config = require("neo_notebooks").config
  local win_width = target_win_width(bufnr)
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

local function clear_image_entry(entry)
  if not entry then
    return
  end
  require("neo_notebooks.kitty").clear_entry(entry)
end

local function render_cell_in_window(bufnr, cell_id)
  local render = require("neo_notebooks.render")
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    local wins = vim.fn.win_findbuf(bufnr)
    if wins and #wins > 0 then
      win = wins[1]
    end
  end
  if win ~= -1 then
    vim.api.nvim_win_call(win, function()
      render.render_cells(bufnr, { cell_id })
    end)
    return true
  end
  return false
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
  local store = get_store(bufnr)
  for _, entry in pairs(store) do
    clear_image_entry(entry)
  end
  set_buf_var(bufnr, "neo_notebooks_output_store", {})
  set_buf_var(bufnr, "neo_notebooks_output_timing", {})
  local scheduler = require("neo_notebooks.scheduler")
  scheduler.request_render(bufnr, { immediate = true })
end

function M.clear_by_id(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return
  end
  local store = get_store(bufnr)
  local existing = store[cell_id]
  if existing then
    clear_image_entry(existing)
  end
  store[cell_id] = nil
  set_buf_var(bufnr, "neo_notebooks_output_store", store)
  local timing_store = get_timing_store(bufnr)
  timing_store[cell_id] = nil
  set_timing_store(bufnr, timing_store)
  if not render_cell_in_window(bufnr, cell_id) then
    local scheduler = require("neo_notebooks.scheduler")
    scheduler.request_render(bufnr, { immediate = true, cell_ids = { cell_id } })
  end
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

function M.get_display_lines(bufnr, cell_id)
  bufnr = bufnr or 0
  local entry = M.get_entry(bufnr, cell_id)
  if not entry or not entry.lines then
    return nil
  end
  if entry.collapsed then
    local collapsed = M.get_collapsed_line(entry)
    if collapsed then
      return { collapsed }
    end
  end
  return entry.lines
end

function M.get_entry(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return nil
  end
  local store = get_store(bufnr)
  return store[cell_id]
end

function M.get_collapsed_line(entry)
  if not entry then
    return nil
  end
  local count = entry.len or (entry.lines and #entry.lines) or 0
  if count == 1 then
    return "output collapsed (1 line)"
  end
  return string.format("output collapsed (%d lines)", count)
end

function M.set_collapsed(bufnr, cell_id, collapsed)
  bufnr = bufnr or 0
  if not cell_id then
    return false
  end
  local store = get_store(bufnr)
  local entry = store[cell_id]
  if not entry then
    return false
  end
  entry.collapsed = collapsed == true
  store[cell_id] = entry
  set_buf_var(bufnr, "neo_notebooks_output_store", store)
  if not render_cell_in_window(bufnr, cell_id) then
    local scheduler = require("neo_notebooks.scheduler")
    scheduler.request_render(bufnr, { immediate = true, cell_ids = { cell_id } })
  end
  return true
end

function M.toggle_collapse(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return nil
  end
  local entry = M.get_entry(bufnr, cell_id)
  if not entry then
    return nil
  end
  local next_state = not entry.collapsed
  if M.set_collapsed(bufnr, cell_id, next_state) then
    return next_state
  end
  return nil
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
      render_lines = with_timing(lines, opts.duration_ms, bufnr)
    end
    if vim.deep_equal(existing_lines, render_lines) then
      if opts.executing then
        if existing then
          clear_image_entry(existing)
        end
        local executing_line = nil
        if render_lines[1] then
          local spinner = require("neo_notebooks.spinner")
          local frame = spinner.get_frame_or_last(bufnr, cell.id) or " "
          executing_line = render_lines[1]
          render_lines[1] = frame .. " " .. executing_line
        end
        store[cell.id] = {
          lines = render_lines,
          len = #render_lines,
          duration_ms = opts.duration_ms,
          executing = true,
          executing_line = executing_line,
          image_placements = opts.image_placements or nil,
        }
        set_buf_var(bufnr, "neo_notebooks_output_store", store)
        if not render_cell_in_window(bufnr, cell.id) then
          local scheduler = require("neo_notebooks.scheduler")
          scheduler.request_render(bufnr, { immediate = true, cell_ids = { cell.id } })
        end
        return
      end
      if opts.duration_ms then
        M.set_timing(bufnr, cell.id, opts.duration_ms)
        if existing then
          existing.duration_ms = opts.duration_ms
          clear_image_entry(existing)
          if opts.image_placements then
            existing.image_placements = opts.image_placements
          end
          store[cell.id] = existing
          set_buf_var(bufnr, "neo_notebooks_output_store", store)
        end
        if not render_cell_in_window(bufnr, cell.id) then
          local scheduler = require("neo_notebooks.scheduler")
          scheduler.request_render(bufnr, { immediate = true, cell_ids = { cell.id } })
        end
      end
      if vim.g.neo_notebooks_debug_output then
        vim.notify("show_inline skipped (same output)", vim.log.levels.INFO)
      end
      return
    end
    local executing = opts.executing == true
    local executing_line = nil
    if executing and render_lines[1] then
      local spinner = require("neo_notebooks.spinner")
      local frame = spinner.get_frame_or_last(bufnr, cell.id) or " "
      executing_line = render_lines[1]
      render_lines[1] = frame .. " " .. executing_line
    end
    clear_image_entry(existing)
    store[cell.id] = {
      lines = render_lines,
      len = #render_lines,
      duration_ms = opts.duration_ms,
      executing = executing,
      executing_line = executing_line,
      collapsed = existing and existing.collapsed or false,
      has_image = opts.has_image == true,
      image_placements = opts.image_placements or (existing and existing.image_placements) or nil,
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
  if not render_cell_in_window(bufnr, cell.id) then
    local scheduler = require("neo_notebooks.scheduler")
    scheduler.request_render(bufnr, { immediate = true, cell_ids = { cell.id } })
  end
end

function M.show_payload(bufnr, cell, payload, opts)
  if payload == nil then
    return
  end
  if type(payload) == "table" and payload.items then
    local prefer_kitty = use_kitty_renderer()
    local image_paths = {}
    local rendered_in_pane = false
    if prefer_kitty and image_target() == "pane" then
      local pane = require("neo_notebooks.image_pane")
      local result = pane.render_items(cell, payload.items) or {}
      image_paths = result.paths or {}
      rendered_in_pane = result.rendered == true
    end
    local lines, has_image, placements =
      render_lines_for_items(bufnr, payload.items, {
        kitty = prefer_kitty,
        cell_id = cell.id,
        image_paths = image_paths,
        rendered_in_pane = rendered_in_pane,
      })
    if placements and opts and opts.duration_ms then
      for _, placement in ipairs(placements) do
        placement.offset = placement.offset + 1
      end
    end
    if prefer_kitty and placements and #placements > 0 then
      opts = opts or {}
      opts.image_placements = placements
    end
    opts = opts or {}
    if has_image then
      opts.has_image = true
    end
    return M.show_inline(bufnr, cell, lines, opts)
  end
  return M.show_inline(bufnr, cell, payload, opts)
end

function M.update_executing_line(bufnr, cell_id, frame)
  bufnr = bufnr or 0
  if not cell_id then
    return
  end
  local store = get_store(bufnr)
  local entry = store[cell_id]
  if not entry or entry.executing ~= true or not entry.executing_line then
    return
  end
  entry.lines = entry.lines or {}
  entry.lines[1] = frame .. " " .. entry.executing_line
  store[cell_id] = entry
  set_buf_var(bufnr, "neo_notebooks_output_store", store)
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

function M.kitty_enabled()
  return use_kitty_renderer()
end

function M.clear(bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
end

function M.clear_images(bufnr, cell_id)
  bufnr = bufnr or 0
  if not cell_id then
    return
  end
  local store = get_store(bufnr)
  local entry = store[cell_id]
  if not entry then
    return
  end
  clear_image_entry(entry)
  entry.image_placements = nil
  store[cell_id] = entry
  set_buf_var(bufnr, "neo_notebooks_output_store", store)
end

return M
