local M = {}

local state = {
  next_id = 1,
  pending = {},
}

local function alloc_id()
  local id = state.next_id
  state.next_id = state.next_id + 1
  return id
end

local function hash_id(seed)
  local hash = 0
  for i = 1, #seed do
    hash = (hash * 31 + seed:byte(i)) % 2000000000
  end
  if hash == 0 then
    hash = alloc_id()
  end
  return hash
end

local function send(data)
  if not data or data == "" then
    return
  end
  local ok = pcall(vim.api.nvim_chan_send, vim.v.stderr, data)
  if ok then
    return
  end
  pcall(vim.api.nvim_out_write, data)
end

local function cursor_goto(row, col)
  return string.format("\27[%d;%dH", row, col)
end

local function kitty_chunks(b64, params)
  if not b64 or b64 == "" then
    return {}
  end
  local prefix = "\27_G"
  local suffix = "\27\\"
  local out = {}
  local chunk_size = 4096
  local i = 1
  local first = true
  while i <= #b64 do
    local chunk = b64:sub(i, i + chunk_size - 1)
    i = i + chunk_size
    local more = i <= #b64
    local header = ""
    if first then
      header = table.concat(params, ",") .. ",m=" .. (more and "1" or "0") .. ";"
      first = false
    else
      header = "m=" .. (more and "1" or "0") .. ";"
    end
    table.insert(out, prefix .. header .. chunk .. suffix)
  end
  return out
end

local function delete_images(list)
  if not list then
    return
  end
  for _, entry in ipairs(list) do
    local image_id = entry.image_id
    local placement_id = entry.placement_id
    if image_id and placement_id then
      local seq = string.format("\27_Ga=d,d=i,i=%d,p=%d\27\\", image_id, placement_id)
      send(seq)
    end
  end
end

local function is_notebook_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return false
  end
  return name:match("%.ipynb$") or name:match("%.nn$")
end

function M.clear_entry(entry)
  if not entry or not entry.kitty_images then
    return
  end
  delete_images(entry.kitty_images)
  entry.kitty_images = nil
  entry.kitty_cache = nil
end

function M.render_entry(bufnr, win, layout, entry)
  if not entry or not entry.image_placements or #entry.image_placements == 0 then
    return
  end
  if win == -1 then
    return
  end

  local wininfo = vim.fn.getwininfo(win)[1]
  if not wininfo then
    return
  end

  local output_lines = entry.lines or {}
  if entry.collapsed then
    output_lines = { require("neo_notebooks.output").get_collapsed_line(entry) }
  end
  local block_height = #output_lines + 2
  local top_line = layout.bottom_line or 0
  local render_col = math.max(0, layout.left_col + 1)

  local images = {}
  entry.kitty_cache = entry.kitty_cache or {}
  if top_line + 1 < wininfo.topline or top_line + 1 > wininfo.botline then
    M.clear_entry(entry)
    return
  end
  local anchor_row = wininfo.winrow + (top_line - wininfo.topline)
  local anchor_col = wininfo.wincol + (wininfo.textoff or 0) + render_col

  for idx, placement in ipairs(entry.image_placements) do
    local item = placement.item
    if item and item.type == "image/png" and item.data then
      local rows = placement.rows or 1
      local cols = placement.cols or (layout.right_col - layout.left_col - 1)
      local offset = (placement.offset or 1) + 1
      local screen_row = anchor_row - (block_height - 1) + offset
      local screen_col = anchor_col
      if screen_row and screen_col and screen_row >= wininfo.winrow and screen_row <= (wininfo.winrow + wininfo.height - 1) then
        local seed = string.format("nb:%s:%d", tostring(entry.cell_id or "0"), idx)
        local image_id = hash_id(seed .. ":i")
        local placement_id = hash_id(seed .. ":p")
        local signature = string.format("%d:%d:%d:%d:%d", screen_row, screen_col, rows, cols, #item.data)
        if entry.kitty_cache[seed] == signature then
          table.insert(images, { image_id = image_id, placement_id = placement_id })
          goto continue
        end
        if entry.kitty_cache[seed] then
          delete_images({ { image_id = image_id, placement_id = placement_id } })
        end
        local params = {
          "a=T",
          "f=100",
          "i=" .. tostring(image_id),
          "p=" .. tostring(placement_id),
          "c=" .. tostring(cols),
          "r=" .. tostring(rows),
          "C=1",
        }
        local chunks = kitty_chunks(item.data, params)
        if #chunks > 0 then
          send("\27[?25l")
          send("\27[s")
          send(cursor_goto(screen_row, screen_col))
          for _, chunk in ipairs(chunks) do
            send(chunk)
          end
          send("\27[u")
          send("\27[?25h")
          table.insert(images, { image_id = image_id, placement_id = placement_id })
          entry.kitty_cache[seed] = signature
        end
      end
    end
    ::continue::
  end

  if entry.kitty_images then
    local current = {}
    for _, img in ipairs(images) do
      current[img.image_id .. ":" .. img.placement_id] = true
    end
    local stale = {}
    for _, img in ipairs(entry.kitty_images) do
      local key = img.image_id .. ":" .. img.placement_id
      if not current[key] then
        table.insert(stale, img)
      end
    end
    if #stale > 0 then
      delete_images(stale)
    end
  end

  if #images > 0 then
    entry.kitty_images = images
  end
end

function M.render_buffer(bufnr, win)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not is_notebook_path(bufnr) then
    return
  end
  if win == nil then
    win = vim.fn.bufwinid(bufnr)
    if win == -1 then
      local wins = vim.fn.win_findbuf(bufnr)
      if wins and #wins > 0 then
        win = wins[1]
      end
    end
  end
  if win == -1 then
    return
  end
  local index = require("neo_notebooks.index")
  local output = require("neo_notebooks.output")
  local state = index.get(bufnr)
  for _, cell in ipairs(state.list or {}) do
    local entry = output.get_entry(bufnr, cell.id)
    if entry and not entry.image_placements then
      M.clear_entry(entry)
    elseif entry and entry.image_placements and output.kitty_enabled() then
      entry.cell_id = cell.id
      if cell.layout then
        M.render_entry(bufnr, win, cell.layout, entry)
      end
    elseif entry then
      M.clear_entry(entry)
    end
  end
end

function M.setup_autocmds()
  if M._autocmds then
    return
  end
  M._autocmds = true
  local group = vim.api.nvim_create_augroup("NeoNotebooksKitty", { clear = true })
  vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized" }, {
    group = group,
    callback = function(args)
      local win = tonumber(args.file)
      if not win or win == 0 then
        win = vim.api.nvim_get_current_win()
      end
      if state.pending[win] then
        return
      end
      state.pending[win] = true
      vim.defer_fn(function()
        state.pending[win] = nil
        if not vim.api.nvim_win_is_valid(win) then
          return
        end
        local bufnr = vim.api.nvim_win_get_buf(win)
        if not bufnr then
          return
        end
        M.render_buffer(bufnr, win)
      end, 30)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWinEnter" }, {
    group = group,
    callback = function(args)
      M.render_buffer(args.buf, vim.api.nvim_get_current_win())
    end,
  })
end

return M
