local containment = require("neo_notebooks.containment")

local M = {}

local function block(reason)
  return { action = "block", reason = reason }
end

local function allow(keys)
  return { action = "allow", keys = keys }
end

local function redirect(target)
  return { action = "redirect", target = target }
end

function M.can_mutate_line(bufnr, line)
  bufnr = bufnr or 0
  local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
  if containment.marker_type(text) then
    return false, "NeoNotebook: cannot edit cell marker line"
  end
  return true
end

function M.can_delete_line(bufnr, line)
  bufnr = bufnr or 0
  local cell = containment.get_cell(bufnr, line)
  if not cell then
    return true
  end
  if cell.border ~= false and line == cell.start then
    return false, "NeoNotebook: cannot delete cell marker line"
  end
  if containment.has_next_marker(bufnr, cell) then
    local keep = math.max(0, (require("neo_notebooks").config.cell_gap_lines or 0))
    local next_marker = cell.finish + 1
    local min_distance = keep + 1
    local distance = next_marker - line
    if distance <= min_distance then
      return false, "NeoNotebook: protected cell bottom spacing"
    end
  end
  return true
end

function M.decide(bufnr, op, ctx)
  bufnr = bufnr or 0
  ctx = ctx or {}
  local state = ctx.state or containment.cursor_state(bufnr)

  if op == "insert_cr" then
    if not state.cell then
      return allow("<CR>")
    end
    if not state.has_body then
      return redirect("open_line_below")
    end
    if state.line < state.body_start then
      return redirect("open_line_below")
    end
    if state.has_next and state.line >= state.protected_floor then
      return redirect("open_line_below")
    end
    return allow("<CR>")
  end

  if op == "insert_bs" then
    if containment.marker_type(state.text) then
      return block("NeoNotebook: cannot edit cell marker line")
    end
    if state.col == 0 and state.line > 0 and containment.marker_type(state.prev_text) then
      return block("NeoNotebook: cannot backspace into cell marker line")
    end
    return allow("<BS>")
  end

  if op == "delete_line" then
    local count = ctx.count or vim.v.count
    if not count or count < 1 then
      count = 1
    end
    for i = 0, count - 1 do
      local ok, reason = M.can_delete_line(bufnr, state.line + i)
      if not ok then
        return block(reason)
      end
    end
    return allow("dd")
  end

  if op == "delete_char" then
    local ok, reason = M.can_mutate_line(bufnr, state.line)
    if not ok then
      return block(reason)
    end
    return allow("x")
  end

  if op == "delete_to_eol" then
    local ok, reason = M.can_mutate_line(bufnr, state.line)
    if not ok then
      return block(reason)
    end
    return allow("D")
  end

  if op == "delete_visual" then
    local mode = ctx.mode or vim.fn.visualmode()
    local first = ctx.first_line
    local last = ctx.last_line
    if first == nil then
      first = vim.fn.line("'<") - 1
    end
    if last == nil then
      last = vim.fn.line("'>") - 1
    end
    if first > last then
      first, last = last, first
    end

    if mode == "V" then
      for line = first, last do
        local ok, reason = M.can_delete_line(bufnr, line)
        if not ok then
          return block(reason)
        end
      end
    else
      for line = first, last do
        local ok, reason = M.can_mutate_line(bufnr, line)
        if not ok then
          return block(reason)
        end
      end
    end
    return allow("d")
  end

  return allow(nil)
end

return M
