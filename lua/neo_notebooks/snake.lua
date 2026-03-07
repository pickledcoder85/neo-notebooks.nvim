local index = require("neo_notebooks.index")

local M = {}

local state_by_buf = {}

math.randomseed(os.time())

local function find_state(bufnr)
  return state_by_buf[bufnr]
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
    "# neo_notebooks snake mode: h/j/k/l move, <Esc> exit",
    string.format("# score: %d", state.score),
    "# +" .. string.rep("-", state.width) .. "+",
  }
  for y = 1, state.height do
    table.insert(lines, "# |" .. table.concat(grid[y], "") .. "|")
  end
  table.insert(lines, "# +" .. string.rep("-", state.width) .. "+")
  if not state.alive then
    table.insert(lines, "# game over (<Esc> to exit snake mode)")
  end
  return lines
end

local function write_cell(bufnr, state)
  local entry = index.get_by_id(bufnr, state.cell_id)
  if not entry then
    return false
  end
  local start_line = entry.start + 1
  local end_line = entry.finish + 1
  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, render_lines(state))
  index.mark_dirty(bufnr)
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
  local width = math.max(8, tonumber(opts.width) or 18)
  local height = math.max(6, tonumber(opts.height) or 10)
  local state = {
    cell_id = cell_id,
    width = width,
    height = height,
    dir = "right",
    score = 0,
    alive = true,
    snake = {
      { x = 3, y = 3 },
      { x = 2, y = 3 },
      { x = 1, y = 3 },
    },
  }
  state.apple = random_apple(state)
  state_by_buf[bufnr] = state
  write_cell(bufnr, state)
  return true
end

function M.move(bufnr, direction)
  bufnr = bufnr or 0
  local state = find_state(bufnr)
  if not state then
    return nil, "Snake mode is not active"
  end
  if not state.alive then
    write_cell(bufnr, state)
    return true
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
    M.stop(bufnr, { delete_cell = true })
    return true, "game_over"
  end

  table.insert(state.snake, 1, { x = nx, y = ny })
  if state.apple and nx == state.apple.x and ny == state.apple.y then
    state.score = state.score + 1
    state.apple = random_apple(state)
  else
    table.remove(state.snake)
  end

  write_cell(bufnr, state)
  return true
end

function M.stop(bufnr, opts)
  bufnr = bufnr or 0
  opts = opts or {}
  local state = find_state(bufnr)
  if not state then
    return false
  end
  local entry = index.get_by_id(bufnr, state.cell_id)
  if entry and opts.delete_cell then
    vim.api.nvim_buf_set_lines(bufnr, entry.start, entry.finish + 1, false, {})
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local target_line = math.max(1, math.min(entry.start + 1, line_count))
    pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
    index.mark_dirty(bufnr)
  elseif entry then
    vim.api.nvim_buf_set_lines(bufnr, entry.start + 1, entry.finish + 1, false, {
      "# snake mode exited",
      "",
    })
    index.mark_dirty(bufnr)
  end
  state_by_buf[bufnr] = nil
  return true
end

return M
