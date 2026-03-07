local index = require("neo_notebooks.index")
local config = require("neo_notebooks").config

local M = {}
M.ns = vim.api.nvim_create_namespace("neo_notebooks_snake")

local state_by_buf = {}

math.randomseed(os.time())

local function find_state(bufnr)
  return state_by_buf[bufnr]
end

local function stop_timer(state)
  if state and state.timer then
    pcall(vim.fn.timer_stop, state.timer)
    state.timer = nil
  end
end

local function occupies_snake(state, x, y)
  for _, part in ipairs(state.snake) do
    if part.x == x and part.y == y then
      return true
    end
  end
  return false
end

local function random_apple(state)
  local free = {}
  for y = 1, state.height do
    for x = 1, state.width do
      if not occupies_snake(state, x, y) then
        table.insert(free, { x = x, y = y })
      end
    end
  end
  if #free == 0 then
    return nil
  end
  return free[math.random(#free)]
end

local function render_lines(state)
  local grid = {}
  for y = 1, state.height do
    local row = {}
    for _ = 1, state.width do
      table.insert(row, " ")
    end
    table.insert(grid, row)
  end

  for i, part in ipairs(state.snake) do
    local row = grid[part.y]
    if row and row[part.x] then
      row[part.x] = i == 1 and "@" or "o"
    end
  end

  if state.apple then
    local row = grid[state.apple.y]
    if row and row[state.apple.x] and row[state.apple.x] == " " then
      row[state.apple.x] = "*"
    end
  end

  local lines = {
    "snake: auto-move, h/j/k/l turn, <Esc> exit",
    string.format("score: %d", state.score),
    "┌" .. string.rep("─", state.width) .. "┐",
  }
  for y = 1, state.height do
    table.insert(lines, "│" .. table.concat(grid[y], "") .. "│")
  end
  table.insert(lines, "└" .. string.rep("─", state.width) .. "┘")
  if not state.alive then
    table.insert(lines, "game over (<Esc> to exit snake mode)")
  end
  return lines
end

local function board_left_col(entry)
  if entry and entry.layout and entry.layout.left_col then
    return entry.layout.left_col + 1
  end
  local win_width = vim.api.nvim_win_get_width(0)
  local ratio = config.cell_width_ratio or 0.9
  local width = math.floor(win_width * ratio)
  width = math.max(config.cell_min_width or 60, width)
  width = math.min(config.cell_max_width or win_width, width)
  width = math.min(width, win_width)
  width = math.max(10, width)
  local pad = math.max(0, math.floor((win_width - width) / 2))
  return pad + 1
end

local function board_cell_width(entry)
  if entry and entry.layout and entry.layout.left_col and entry.layout.right_col then
    return math.max(1, (entry.layout.right_col - entry.layout.left_col) + 1)
  end
  local win_width = vim.api.nvim_win_get_width(0)
  local ratio = config.cell_width_ratio or 0.9
  local width = math.floor(win_width * ratio)
  width = math.max(config.cell_min_width or 60, width)
  width = math.min(config.cell_max_width or win_width, width)
  width = math.min(width, win_width)
  return math.max(10, width)
end

local function resolve_board_width(entry, opts)
  if opts and opts.width ~= nil then
    return math.max(8, tonumber(opts.width) or 18)
  end
  local cell_width = board_cell_width(entry)
  -- Keep the board (including box chars) inside the notebook cell interior.
  local derived = cell_width - 4
  return math.max(8, math.min(derived, 48))
end

local function ensure_board_rows(bufnr, state)
  local entry = index.get_by_id(bufnr, state.cell_id)
  if not entry then
    return false
  end
  local required = state.height + 4
  local start_line = entry.start + 1
  local end_line = entry.finish + 1
  local blanks = {}
  for _ = 1, required do
    table.insert(blanks, "")
  end
  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, blanks)
  index.mark_dirty(bufnr)
  return true
end

local function render_overlay(bufnr, state)
  local entry = index.get_by_id(bufnr, state.cell_id)
  if not entry then
    return false
  end
  local start_line = entry.start + 1
  local end_line = entry.finish + 1
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, start_line, end_line)
  local lines = render_lines(state)
  local left = board_left_col(entry)
  for i, line in ipairs(lines) do
    local lnum = start_line + i - 1
    if lnum <= end_line then
      vim.api.nvim_buf_set_extmark(bufnr, M.ns, lnum, 0, {
        virt_text = { { line, "Comment" } },
        virt_text_pos = "overlay",
        virt_text_win_col = left,
        priority = 160,
      })
    end
  end
  return true
end

function M.is_active(bufnr)
  return find_state(bufnr or 0) ~= nil
end

function M.start(bufnr, cell_id, opts)
  bufnr = bufnr or 0
  opts = opts or {}
  local entry = index.get_by_id(bufnr, cell_id)
  if not entry or entry.type ~= "code" then
    return nil, "Snake mode requires a code cell"
  end
  require("neo_notebooks.render").render(bufnr)
  entry = index.get_by_id(bufnr, cell_id) or entry
  local width = resolve_board_width(entry, opts)
  local height = math.max(5, tonumber(opts.height) or 5)
  local state = {
    cell_id = cell_id,
    width = width,
    height = height,
    dir = "right",
    score = 0,
    alive = true,
    on_exit = opts.on_exit,
    tick_ms = math.max(40, tonumber(opts.tick_ms) or 320),
    min_tick_ms = math.max(30, tonumber(opts.min_tick_ms) or 80),
    speed_step_ms = math.max(1, tonumber(opts.speed_step_ms) or 25),
    auto = opts.auto ~= false,
    timer = nil,
    snake = {
      { x = 3, y = 3 },
      { x = 2, y = 3 },
      { x = 1, y = 3 },
    },
  }
  state.apple = random_apple(state)
  state_by_buf[bufnr] = state
  if not ensure_board_rows(bufnr, state) then
    state_by_buf[bufnr] = nil
    return nil, "Snake mode could not prepare cell rows"
  end
  require("neo_notebooks.render").render(bufnr)
  render_overlay(bufnr, state)
  if state.auto then
    state.timer = vim.fn.timer_start(state.tick_ms, vim.schedule_wrap(function()
      if not state_by_buf[bufnr] then
        return
      end
      M.move(bufnr)
    end), { ["repeat"] = -1 })
  end
  return true
end

function M.set_direction(bufnr, direction)
  bufnr = bufnr or 0
  local state = find_state(bufnr)
  if not state then
    return nil, "Snake mode is not active"
  end
  local opposite = {
    left = "right",
    right = "left",
    up = "down",
    down = "up",
  }
  if direction and opposite[direction] ~= state.dir then
    state.dir = direction
  end
  return true
end

function M.move(bufnr, direction)
  bufnr = bufnr or 0
  local state = find_state(bufnr)
  if not state then
    return nil, "Snake mode is not active"
  end
  if not state.alive then
    render_overlay(bufnr, state)
    return true
  end

  if direction then
    local ok_dir, err_dir = M.set_direction(bufnr, direction)
    if not ok_dir then
      return nil, err_dir
    end
  end

  local head = state.snake[1]
  local dx, dy = 0, 0
  if state.dir == "left" then
    dx = -1
  elseif state.dir == "right" then
    dx = 1
  elseif state.dir == "up" then
    dy = -1
  else
    dy = 1
  end

  local nx = head.x + dx
  local ny = head.y + dy
  if nx < 1 or nx > state.width or ny < 1 or ny > state.height or occupies_snake(state, nx, ny) then
    state.alive = false
    M.stop(bufnr, { delete_cell = true, reason = "game_over" })
    return true, "game_over"
  end

  table.insert(state.snake, 1, { x = nx, y = ny })
  if state.apple and nx == state.apple.x and ny == state.apple.y then
    state.score = state.score + 1
    state.apple = random_apple(state)
    if state.auto then
      state.tick_ms = math.max(state.min_tick_ms, state.tick_ms - state.speed_step_ms)
      stop_timer(state)
      state.timer = vim.fn.timer_start(state.tick_ms, vim.schedule_wrap(function()
        if not state_by_buf[bufnr] then
          return
        end
        M.move(bufnr)
      end), { ["repeat"] = -1 })
    end
  else
    table.remove(state.snake)
  end

  render_overlay(bufnr, state)
  return true
end

function M.stop(bufnr, opts)
  bufnr = bufnr or 0
  opts = opts or {}
  local state = find_state(bufnr)
  if not state then
    return false
  end
  stop_timer(state)
  local entry = index.get_by_id(bufnr, state.cell_id)
  if entry and opts.delete_cell then
    vim.api.nvim_buf_clear_namespace(bufnr, M.ns, entry.start + 1, entry.finish + 1)
    vim.api.nvim_buf_set_lines(bufnr, entry.start, entry.finish + 1, false, {})
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local target_line = math.max(1, math.min(entry.start + 1, line_count))
    pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
    index.mark_dirty(bufnr)
  elseif entry then
    vim.api.nvim_buf_clear_namespace(bufnr, M.ns, entry.start + 1, entry.finish + 1)
  end
  state_by_buf[bufnr] = nil
  if type(state.on_exit) == "function" then
    pcall(state.on_exit, opts.reason or "stopped")
  end
  return true
end

return M
