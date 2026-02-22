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

local function output_block(lines, width, pad, hl)
  local block = {}
  local function border(left, right)
    return string.rep(" ", pad) .. cell_border(width, left, right)
  end

  -- Output block top border: downward corners.
  table.insert(block, { { border("╭", "╮"), hl } })
  local inner_width = math.max(0, width - 2)
  for _, line in ipairs(lines) do
    local clipped = pad_text(line, inner_width)
    local body = string.rep(" ", pad) .. "│" .. clipped .. "│"
    table.insert(block, { { body, hl } })
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

  for idx, cell in ipairs(cells_list) do
    if cell.finish < cell.start then
      goto continue
    end

    local top = string.rep(" ", pad) .. cell_border(width, "╭", "╮")
    local bottom = string.rep(" ", pad) .. cell_border(width, "╰", "╯")
    local label = string.format("[%s]", cell.type)
    if config.show_cell_index then
      label = string.format("[%d %s]", idx, cell.type)
    end

    local hl = config.border_hl_code or "Comment"
    if cell.type == "markdown" then
      hl = config.border_hl_markdown or hl
    end

    local label_width = vim.fn.strdisplaywidth(label)
    local label_col = math.max(pad + 1, pad + width - label_width - 1)
    -- No extra top margin; keep the first cell aligned to the window edge.
    local top_lines = { { { top, hl } } }
    if idx == 1 and cell.start == 0 then
      local pad_lines = config.top_padding or 0
      for _ = 1, pad_lines do
        table.insert(top_lines, 1, { { "", hl } })
      end
    end

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

    local finish_line = math.min(math.max(cell.finish, 0), math.max(line_count - 1, 0))
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
      local end_line = math.min(math.max(cell.finish, 0), math.max(line_count - 1, 0))
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
