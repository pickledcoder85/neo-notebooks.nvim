local cells = require("neo_notebooks.cells")
local output = require("neo_notebooks.output")
local config = require("neo_notebooks").config

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

local function output_block(lines, width, pad, hl)
  local block = {}
  local function border(left, right)
    return string.rep(" ", pad) .. cell_border(width, left, right)
  end

  -- Output block top border: downward corners.
  table.insert(block, { { border("╭", "╮"), hl } })
  local inner_width = math.max(0, width - 2)
  for _, line in ipairs(lines) do
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
  end
  table.insert(block, { { border("╰", "╯"), hl } })
  return block
end

function M.clear(bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
end

function M.render(bufnr)
  bufnr = bufnr or 0
  M.clear(bufnr)
  local win_width = vim.api.nvim_win_get_width(0)
  local ratio = config.cell_width_ratio or 0.9
  local width = math.floor(win_width * ratio)
  width = math.max(config.cell_min_width or 60, width)
  width = math.min(config.cell_max_width or win_width, width)
  width = math.min(width, win_width)
  width = math.max(10, width)
  local pad = math.max(0, math.floor((win_width - width) / 2))
  local index = cells.get_cells_indexed(bufnr)
  local cells_list = index.list or {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  local function get_buf_var(name, default)
    local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, name)
    if ok then
      return value
    end
    return default
  end

  local function set_buf_var(name, value)
    vim.api.nvim_buf_set_var(bufnr, name, value)
  end

  local function clear_tail_pad()
    local pad = get_buf_var("neo_notebooks_tail_pad", 0)
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
    set_buf_var("neo_notebooks_tail_pad", 0)
    line_count = vim.api.nvim_buf_line_count(bufnr)
  end

  local function ensure_tail_pad(lines)
    clear_tail_pad()
    if lines <= 0 then
      return
    end
    local blanks = {}
    for _ = 1, lines do
      table.insert(blanks, "")
    end
    vim.api.nvim_buf_set_lines(bufnr, line_count, line_count, false, blanks)
    set_buf_var("neo_notebooks_tail_pad", lines)
    line_count = vim.api.nvim_buf_line_count(bufnr)
  end

  local visible_idx = 0
  for _, cell in ipairs(cells_list) do
    if cell.finish < cell.start or cell.border == false then
      goto continue
    end
    visible_idx = visible_idx + 1

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
    -- No extra top margin; keep the first cell aligned to the window edge.
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
      local out_lines = output.get_lines(bufnr, cell.id)
      if out_lines and #out_lines > 0 then
        local out_block = output_block(out_lines, width, pad, "NeoNotebookOutput")
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
        render_finish = math.max(last_nonempty, cell.start + 1)
      end
    end
    local finish_line = math.min(math.max(render_finish, 0), math.max(line_count - 1, 0))
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
      local left_col = pad
      local right_col = math.max(pad, pad + width - 1)
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

    ::continue::
  end

  -- Add trailing padding so the last cell output is scrollable.
  local tail_pad = 0
  local last = cells_list[#cells_list]
  if last and last.type == "code" then
    local out_lines = output.get_lines(bufnr, last.id)
    if out_lines and #out_lines > 0 then
      -- top border + content + bottom border
      tail_pad = #out_lines + 2
    end
  end
  if tail_pad > 0 then
    ensure_tail_pad(tail_pad)
  else
    clear_tail_pad()
  end
end

return M
