local cells = require("neo_notebooks.cells")
local output = require("neo_notebooks.output")
local config = require("neo_notebooks").config
local containment = require("neo_notebooks.containment")
local spinner = require("neo_notebooks.spinner")

local M = {}

M.ns = vim.api.nvim_create_namespace("neo_notebooks_cells")

local function cell_border(width, left, right)
  if width < 2 then
    return left .. right
  end
  return left .. string.rep("─", width - 2) .. right
end

local function pad_text(text, width)
  if width <= 0 then
    return ""
  end
  local display = vim.fn.strdisplaywidth(text)
  if display > width then
    text = vim.fn.strcharpart(text, 0, width)
    display = vim.fn.strdisplaywidth(text)
  end
  if display < width then
    text = text .. string.rep(" ", width - display)
  end
  return text
end

local ANSI_COLORS = {
  [30] = "Black",
  [31] = "Red",
  [32] = "Green",
  [33] = "Yellow",
  [34] = "Blue",
  [35] = "Magenta",
  [36] = "Cyan",
  [37] = "White",
  [90] = "BrightBlack",
  [91] = "BrightRed",
  [92] = "BrightGreen",
  [93] = "BrightYellow",
  [94] = "BrightBlue",
  [95] = "BrightMagenta",
  [96] = "BrightCyan",
  [97] = "BrightWhite",
}

local function ansi_chunks(line, base_hl)
  local chunks = {}
  local i = 1
  local state = { fg = nil, bold = false }

  local function current_hl()
    if not state.fg then
      return base_hl
    end
    local name = "NeoNotebookAnsi" .. state.fg
    if state.bold then
      name = name .. "Bold"
    end
    return name
  end

  while true do
    local s, e, seq = line:find("\27%[([0-9;]*)m", i)
    local text = line:sub(i, (s or (#line + 1)) - 1)
    if text ~= "" then
      table.insert(chunks, { text, current_hl() })
    end
    if not s then
      break
    end
    local codes = {}
    if seq == "" then
      codes = { 0 }
    else
      for code in seq:gmatch("[0-9]+") do
        table.insert(codes, tonumber(code))
      end
    end
    for _, code in ipairs(codes) do
      if code == 0 then
        state = { fg = nil, bold = false }
      elseif code == 1 then
        state.bold = true
      elseif code == 22 then
        state.bold = false
      elseif code == 39 then
        state.fg = nil
      elseif ANSI_COLORS[code] then
        state.fg = ANSI_COLORS[code]
      end
    end
    i = e + 1
  end

  if #chunks == 0 then
    return { { "", base_hl } }
  end
  return chunks
end

local function truncate_chunks(chunks, width, base_hl)
  if width <= 0 then
    return {}
  end
  local out = {}
  local remaining = width
  for _, chunk in ipairs(chunks) do
    local text, hl = chunk[1], chunk[2]
    local w = vim.fn.strdisplaywidth(text)
    if w <= remaining then
      table.insert(out, { text, hl })
      remaining = remaining - w
    else
      local truncated = vim.fn.strcharpart(text, 0, remaining)
      if truncated ~= "" then
        table.insert(out, { truncated, hl })
      end
      remaining = 0
      break
    end
  end
  if remaining > 0 then
    table.insert(out, { string.rep(" ", remaining), base_hl })
  end
  return out
end

local function format_duration(duration_ms)
  if type(duration_ms) == "table" then
    duration_ms = duration_ms.duration_ms
  end
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

local function output_block(lines, width, pad, hl, spin, reserve_spin)
  local block = {}
  local function border(left, right)
    return string.rep(" ", pad) .. cell_border(width, left, right)
  end

  -- Output block top border: downward corners.
  local top_border = border("╭", "╮")
  table.insert(block, { { top_border, hl } })

  local inner_width = math.max(0, width - 2)
  for i, line in ipairs(lines) do
    if i == 1 and (spin or reserve_spin) then
      local frame = spin or " "
      line = frame .. " " .. line
    end
    local timing_label = nil
    local timing_leading = nil
    if i == 1 and line:find("^%s*%[") and line:find("%]$") then
      timing_label = line:match("(%[[^%]]+%])")
      timing_leading = line:match("^(%s*)") or ""
    end
    if timing_label then
      local used = vim.fn.strdisplaywidth(timing_leading) + vim.fn.strdisplaywidth(timing_label)
      local right_pad = math.max(0, inner_width - used)
      local row = {}
      table.insert(row, { string.rep(" ", pad) .. "│", hl })
      if timing_leading ~= "" then
        table.insert(row, { timing_leading, hl })
      end
      table.insert(row, { timing_label, "Identifier" })
      if right_pad > 0 then
        table.insert(row, { string.rep(" ", right_pad), hl })
      end
      table.insert(row, { "│", hl })
      table.insert(block, row)
      goto continue
    end
    local use_ansi = line:find("\27%[") ~= nil
    local chunks = (use_ansi and ansi_chunks(line, hl)) or { { line, hl } }
    local clipped = truncate_chunks(chunks, inner_width, hl)
    local row = {}
    table.insert(row, { string.rep(" ", pad) .. "│", hl })
    for _, chunk in ipairs(clipped) do
      table.insert(row, chunk)
    end
    table.insert(row, { "│", hl })
    table.insert(block, row)
    ::continue::
  end
  table.insert(block, { { border("╰", "╯"), hl } })
  return block
end

local function get_buf_var(bufnr, name, default)
  local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, name)
  if ok then
    return value
  end
  return default
end

local function set_buf_var(bufnr, name, value)
  vim.api.nvim_buf_set_var(bufnr, name, value)
end

local function compute_layout(bufnr)
  local win_width = vim.api.nvim_win_get_width(0)
  local ratio = config.cell_width_ratio or 0.9
  local width = math.floor(win_width * ratio)
  width = math.max(config.cell_min_width or 60, width)
  width = math.min(config.cell_max_width or win_width, width)
  width = math.min(width, win_width)
  width = math.max(10, width)
  local pad = math.max(0, math.floor((win_width - width) / 2))
  return {
    win_width = win_width,
    width = width,
    pad = pad,
  }
end

local function clear_tail_pad(bufnr)
  local pad = get_buf_var(bufnr, "neo_notebooks_tail_pad", 0)
  if pad <= 0 then
    return
  end
  local current = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local total = #current
  local can_remove = true
  for i = total - pad + 1, total do
    local line = current[i]
    if line ~= "" then
      can_remove = false
      break
    end
  end
  if can_remove then
    vim.api.nvim_buf_set_lines(bufnr, total - pad, total, false, {})
  end
  set_buf_var(bufnr, "neo_notebooks_tail_pad", 0)
end

local function ensure_tail_pad(bufnr, lines)
  clear_tail_pad(bufnr)
  if lines <= 0 then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local blanks = {}
  for _ = 1, lines do
    table.insert(blanks, "")
  end
  vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, blanks)
  set_buf_var(bufnr, "neo_notebooks_tail_pad", lines)
end

local function update_tail_pad(bufnr, cells_list)
  local tail_pad = 0
  local last = cells_list[#cells_list]
  if last and last.type == "code" then
    local out_lines = output.get_lines(bufnr, last.id)
    if out_lines and #out_lines > 0 then
      tail_pad = #out_lines + 2
    end
  end
  local min_pad = config.notebook_scrolloff or 0
  if min_pad > 0 then
    tail_pad = math.max(tail_pad, min_pad)
  end
  if tail_pad > 0 then
    ensure_tail_pad(bufnr, tail_pad)
  else
    clear_tail_pad(bufnr)
  end
end

local function compute_visible_indices(cells_list)
  local map = {}
  local visible_idx = 0
  for _, cell in ipairs(cells_list) do
    if cell.finish >= cell.start and cell.border ~= false then
      visible_idx = visible_idx + 1
      map[cell.id] = visible_idx
    end
  end
  return map
end

local function clear_cell_namespace(bufnr, cell)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local start = math.min(math.max(cell.start, 0), math.max(line_count - 1, 0))
  local finish = math.min(line_count, cell.finish + 1)
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, start, finish)
end

local function render_cell(bufnr, ctx, cell, visible_idx, active, in_insert, cursor_line, line_count)
  if cell.finish < cell.start or cell.border == false then
    return
  end

  local width = ctx.width
  local pad = ctx.pad

  local top = string.rep(" ", pad) .. cell_border(width, "╭", "╮")
  local bottom = string.rep(" ", pad) .. cell_border(width, "╰", "╯")
  local label = string.format("[%s]", cell.type)
  if config.show_cell_index then
    label = string.format("[%d %s]", visible_idx, cell.type)
  end

  local hl = config.border_hl_code or "Comment"
  if cell.type == "markdown" then
    hl = config.border_hl_markdown or hl
  end

  local label_width = vim.fn.strdisplaywidth(label)
  local label_col = math.max(pad + 1, pad + width - label_width - 1)
  local top_lines = { { { top, hl } } }

  vim.api.nvim_buf_set_extmark(bufnr, M.ns, cell.start, 0, {
    virt_lines = top_lines,
    virt_lines_above = true,
    virt_text = { { label, "Identifier" } },
    virt_text_pos = "overlay",
    virt_text_win_col = label_col,
    priority = 100,
  })

  local bottom_lines = { { { bottom, hl } } }
  if cell.type == "code" then
    local out_entry = output.get_entry(bufnr, cell.id)
    local out_lines = out_entry and out_entry.lines or nil
    if out_lines and #out_lines > 0 then
      local spin = spinner.get_frame_or_last(bufnr, cell.id)
      local reserve_spin = out_entry and out_entry.executing == true
      local out_block = output_block(out_lines, width, pad, "NeoNotebookOutput", spin, reserve_spin)
      for _, line in ipairs(out_block) do
        table.insert(bottom_lines, line)
      end
    end
  end

  local render_finish = cell.finish
  if cell.finish >= cell.start + 1 then
    local lines = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
    local last_nonempty = nil
    for i = #lines, 1, -1 do
      if lines[i] ~= "" then
        last_nonempty = cell.start + i
        break
      end
    end
    if last_nonempty then
      render_finish = math.max(last_nonempty + 1, cell.start + 1)
    end
  end
  render_finish = math.min(render_finish, cell.finish)
  if in_insert and active and active.id == cell.id then
    local keep = 0
    if containment.has_next_marker(bufnr, cell) then
      keep = math.max(0, config.cell_gap_lines or 0)
    end
    local max_visible = math.max(cell.start + 1, cell.finish - keep)
    local cursor_clamped = math.max(cell.start + 1, math.min(cursor_line, max_visible))
    render_finish = math.max(render_finish, cursor_clamped)
  end
  local finish_line = math.min(math.max(render_finish, 0), math.max(line_count - 1, 0))
  local left_col = pad
  local right_col = math.max(pad, pad + width - 1)
  cell.layout = {
    left_col = left_col,
    right_col = right_col,
    top_line = cell.start,
    bottom_line = finish_line,
  }
  local index_mod = require("neo_notebooks.index")
  index_mod.set_layout(bufnr, cell.id, cell.layout)
  local bottom_opts = {
    virt_lines = bottom_lines,
    priority = 100,
  }
  if cell.type == "code" then
    local lang = "Python"
    local lang_width = vim.fn.strdisplaywidth(lang)
    local lang_col = math.max(pad + 1, pad + width - lang_width - 1)
    bottom_opts.virt_text = { { lang, "Identifier" } }
    bottom_opts.virt_text_pos = "overlay"
    bottom_opts.virt_text_win_col = lang_col
  end
  vim.api.nvim_buf_set_extmark(bufnr, M.ns, finish_line, 0, bottom_opts)

  if config.vertical_borders then
    local text_pad = string.rep(" ", pad + 1)
    local start_line = math.min(math.max(cell.start, 0), math.max(line_count - 1, 0))
    local end_line = math.min(math.max(render_finish, 0), math.max(line_count - 1, 0))
    if start_line <= end_line then
      for line = start_line, end_line do
        vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {
          virt_text = { { text_pad, hl } },
          virt_text_pos = "inline",
          right_gravity = false,
          priority = 120,
        })
        vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {
          virt_text = { { "│", hl } },
          virt_text_pos = "overlay",
          virt_text_win_col = left_col,
        })
        vim.api.nvim_buf_set_extmark(bufnr, M.ns, line, 0, {
          virt_text = { { "│", hl } },
          virt_text_pos = "overlay",
          virt_text_win_col = right_col,
        })
      end
    end
  end
end

function M.clear(bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
end

function M.render(bufnr)
  bufnr = bufnr or 0
  local index_mod = require("neo_notebooks.index")
  local state = index_mod.get(bufnr)
  M.clear(bufnr)
  local cells_list = state.list or {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local ctx = compute_layout(bufnr)
  local visible_map = compute_visible_indices(cells_list)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local mode = vim.api.nvim_get_mode().mode
  local in_insert = mode:sub(1, 1) == "i"
  local active = containment.get_cell(bufnr, cursor_line)
  for _, cell in ipairs(cells_list) do
    local visible_idx = visible_map[cell.id] or 0
    render_cell(bufnr, ctx, cell, visible_idx, active, in_insert, cursor_line, line_count)
  end
  update_tail_pad(bufnr, cells_list)
end

function M.render_cells(bufnr, cell_ids)
  bufnr = bufnr or 0
  if not cell_ids or #cell_ids == 0 then
    return
  end
  local index_mod = require("neo_notebooks.index")
  local state = index_mod.get(bufnr)
  local cells_list = state.list or {}
  local cell_set = {}
  for _, id in ipairs(cell_ids) do
    cell_set[id] = true
  end
  local ctx = compute_layout(bufnr)
  local visible_map = compute_visible_indices(cells_list)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local mode = vim.api.nvim_get_mode().mode
  local in_insert = mode:sub(1, 1) == "i"
  local active = containment.get_cell(bufnr, cursor_line)
  local last = cells_list[#cells_list]
  local touches_last = last and cell_set[last.id]

  for _, cell in ipairs(cells_list) do
    if cell_set[cell.id] then
      clear_cell_namespace(bufnr, cell)
      local visible_idx = visible_map[cell.id] or 0
      render_cell(bufnr, ctx, cell, visible_idx, active, in_insert, cursor_line, line_count)
    end
  end

  if touches_last then
    update_tail_pad(bufnr, cells_list)
  end
end

return M
