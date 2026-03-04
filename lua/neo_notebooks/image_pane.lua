local M = {}

local state = {
  tty = nil,
  pane_id = nil,
  history = {},
  size_index = 1,
  disabled = false,
  page_index = 0,
}

local sync_size_index
local pane_exists
local pane_title = "neo_notebooks_image"

local function tmp_dir()
  local config = require("neo_notebooks").config
  return config.image_pane_tmp_dir or "/tmp/neo_notebooks-images"
end

local function ensure_tmp_dir()
  local dir = tmp_dir()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function write_temp_image(b64, ext, cell_id, idx)
  local dir = ensure_tmp_dir()
  local safe_id = tostring(cell_id or "cell")
  local suffix = idx and tostring(idx) or "1"
  local filename = string.format("%s_%s.%s", safe_id, suffix, ext)
  local path = dir .. "/" .. filename
  local ok, bytes = pcall(vim.base64.decode, b64)
  if not ok or not bytes then
    return nil
  end
  local fh = io.open(path, "wb")
  if not fh then
    return nil
  end
  fh:write(bytes)
  fh:close()
  return path
end

local function read_file_bytes(path)
  local fh = io.open(path, "rb")
  if not fh then
    return nil
  end
  local data = fh:read("*a")
  fh:close()
  return data
end

local function read_u32_be(s, i)
  local b1, b2, b3, b4 = s:byte(i, i + 3)
  if not b4 then
    return nil
  end
  return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
end

local function read_u16_be(s, i)
  local b1, b2 = s:byte(i, i + 1)
  if not b2 then
    return nil
  end
  return b1 * 256 + b2
end

local function read_image_size(path)
  local data = read_file_bytes(path)
  if not data or #data < 24 then
    return nil, nil
  end
  -- PNG: width/height at bytes 17-24
  if data:sub(1, 8) == "\137PNG\r\n\26\n" then
    local w = read_u32_be(data, 17)
    local h = read_u32_be(data, 21)
    return w, h
  end
  -- JPEG: scan for SOF markers
  if data:byte(1) == 0xFF and data:byte(2) == 0xD8 then
    local i = 3
    while i < #data do
      if data:byte(i) ~= 0xFF then
        i = i + 1
      else
        local marker = data:byte(i + 1)
        if not marker then
          break
        end
        -- SOF0/1/2/3/5/6/7/9/10/11/13/14/15
        if marker == 0xC0 or marker == 0xC1 or marker == 0xC2 or marker == 0xC3
          or marker == 0xC5 or marker == 0xC6 or marker == 0xC7
          or marker == 0xC9 or marker == 0xCA or marker == 0xCB
          or marker == 0xCD or marker == 0xCE or marker == 0xCF then
          local h = read_u16_be(data, i + 5)
          local w = read_u16_be(data, i + 7)
          return w, h
        else
          local len = read_u16_be(data, i + 2)
          if not len then
            break
          end
          i = i + 2 + len
        end
      end
    end
  end
  return nil, nil
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

local function tty_path()
  local config = require("neo_notebooks").config
  return config.image_pane_tty or state.tty
end

local function tmux_available()
  return vim.env.TMUX and vim.fn.executable("tmux") == 1
end

pane_exists = function()
  if not tmux_available() or not state.pane_id then
    return false
  end
  local out = vim.fn.systemlist({ "tmux", "display-message", "-t", state.pane_id, "-p", "#{pane_id}" })
  if vim.v.shell_error ~= 0 or not out or not out[1] then
    return false
  end
  return out[1]:match("%%") ~= nil
end

local function current_session_name()
  local out = vim.fn.systemlist({ "tmux", "display-message", "-p", "#{session_name}" })
  if vim.v.shell_error ~= 0 or not out or not out[1] then
    return nil
  end
  return out[1]
end

local function find_existing_pane()
  if not tmux_available() then
    return nil, nil
  end
  local session = current_session_name()
  local out = vim.fn.systemlist({ "tmux", "list-panes", "-a", "-F", "#{pane_id} #{pane_tty} #{session_name} #{pane_title}" })
  if vim.v.shell_error ~= 0 then
    return nil, nil
  end
  for _, line in ipairs(out or {}) do
    local pid, ptty, sess, title = line:match("^(%%[%d]+)%s+(%S+)%s+(%S+)%s*(.*)$")
    if pid and ptty and title == pane_title and (not session or sess == session) then
      return pid, ptty
    end
  end
  return nil, nil
end

local function tmux_split_get_tty()
  local config = require("neo_notebooks").config
  local percent = tonumber(config.image_pane_tmux_percent)
  if not percent or percent < 1 or percent > 99 then
    percent = 25
  end
  local target = vim.env.TMUX_PANE
  local zoom_cmd
  if target and target ~= "" then
    zoom_cmd = { "tmux", "display-message", "-t", target, "-p", "#{window_zoomed_flag}" }
  else
    zoom_cmd = { "tmux", "display-message", "-p", "#{window_zoomed_flag}" }
  end
  local zoom = vim.fn.systemlist(zoom_cmd)
  if zoom and zoom[1] == "1" then
    local zoom_toggle
    if target and target ~= "" then
      zoom_toggle = { "tmux", "resize-pane", "-t", target, "-Z" }
    else
      zoom_toggle = { "tmux", "resize-pane", "-Z" }
    end
    vim.fn.system(zoom_toggle)
  end
  local cmd
  if target and target ~= "" then
    cmd = { "tmux", "split-window", "-t", target, "-h", "-p", tostring(percent), "-P", "-F", "#{pane_id} #{pane_tty}" }
  else
    cmd = { "tmux", "split-window", "-h", "-p", tostring(percent), "-P", "-F", "#{pane_id} #{pane_tty}" }
  end
  local output = vim.fn.systemlist(cmd)
  if vim.g.neo_notebooks_debug_output then
    vim.notify("NeoNotebook: tmux split cmd: " .. table.concat(cmd, " "), vim.log.levels.INFO)
  end
  if vim.v.shell_error ~= 0 then
    if vim.g.neo_notebooks_debug_output then
      vim.notify("NeoNotebook: tmux split error: " .. table.concat(output or {}, " "), vim.log.levels.WARN)
    end
    -- fallback: compute width and use -l
    local width_cmd
    if target and target ~= "" then
      width_cmd = { "tmux", "display-message", "-t", target, "-p", "#{window_width}" }
    else
      width_cmd = { "tmux", "display-message", "-p", "#{window_width}" }
    end
    local width_out = vim.fn.systemlist(width_cmd)
    local win_width = tonumber(width_out and width_out[1]) or 0
    local cols = math.max(20, math.floor(win_width * (percent / 100)))
    if target and target ~= "" then
      cmd = { "tmux", "split-window", "-t", target, "-h", "-l", tostring(cols), "-P", "-F", "#{pane_id} #{pane_tty}" }
    else
      cmd = { "tmux", "split-window", "-h", "-l", tostring(cols), "-P", "-F", "#{pane_id} #{pane_tty}" }
    end
    output = vim.fn.systemlist(cmd)
    if vim.g.neo_notebooks_debug_output then
      vim.notify("NeoNotebook: tmux split fallback cmd: " .. table.concat(cmd, " "), vim.log.levels.INFO)
    end
    if vim.v.shell_error ~= 0 then
      if vim.g.neo_notebooks_debug_output then
        vim.notify("NeoNotebook: tmux split fallback error: " .. table.concat(output or {}, " "), vim.log.levels.WARN)
      end
      return nil
    end
  end
  if not output or not output[1] or output[1] == "" then
    return nil
  end
  local pane_line = output[1]
  local pane_id, pane_tty = pane_line:match("^(%%[%d]+)%s+(%S+)$")
  if not pane_id then
    pane_tty = pane_line
  end
  if pane_id then
    vim.fn.system({ "tmux", "select-pane", "-t", pane_id, "-T", pane_title })
  end
  local select
  if target and target ~= "" then
    select = { "tmux", "select-pane", "-t", target, "-l" }
  else
    select = { "tmux", "select-pane", "-l" }
  end
  vim.fn.system(select)
  return pane_tty, pane_id
end


local function ensure_tty(open_ok)
  if state.disabled and not open_ok then
    return nil
  end
  if state.pane_id and not pane_exists() then
    state.tty = nil
    state.pane_id = nil
  end
  if (not state.pane_id or not state.tty) and tmux_available() and not state.disabled then
    local existing_id, existing_tty = find_existing_pane()
    if existing_id and existing_tty then
      state.pane_id = existing_id
      state.tty = existing_tty
      sync_size_index()
      return state.tty
    end
  end
  if state.tty and state.tty ~= "" then
    return state.tty
  end
  local config = require("neo_notebooks").config
  local path = config.image_pane_tty
  if path and path ~= "" then
    state.tty = path
    return path
  end
  if tmux_available() and (open_ok or not state.disabled) then
    local created_tty, created_id = tmux_split_get_tty()
    if created_tty and created_tty ~= "" then
      state.tty = created_tty
      state.pane_id = created_id
      sync_size_index()
      state.disabled = false
      if vim.g.neo_notebooks_debug_output then
        local msg = "NeoNotebook: image pane TTY " .. created_tty
        if created_id then
          msg = msg .. " pane " .. created_id
        end
        vim.notify(msg, vim.log.levels.INFO)
      end
      return created_tty
    end
    if vim.g.neo_notebooks_debug_output then
      vim.notify("NeoNotebook: tmux split failed; no pane TTY", vim.log.levels.WARN)
    end
  end
  return nil
end

local function kitty_payload(b64, params)
  if not b64 or b64 == "" then
    return nil
  end
  local prefix = "\27_G"
  local suffix = "\27\\"
  local header = table.concat(params, ",") .. ",m=0;"
  return prefix .. header .. b64 .. suffix
end

local function tmux_wrap(data)
  local escaped = data:gsub("\27", "\27\27")
  return "\27Ptmux;" .. escaped .. "\27\\"
end

local function send(data)
  if not data or data == "" then
    return
  end
  local path = tty_path()
  if not path then
    return
  end
  local ok, fh = pcall(io.open, path, "ab")
  if not ok or not fh then
    return
  end
  fh:write(data)
  fh:close()
end

local function send_kitty(data)
  if not data or data == "" then
    return
  end
  if vim.env.TMUX then
    data = tmux_wrap(data)
  end
  send(data)
end

local function send_kitty_delete_all()
  send_kitty("\27_Ga=d\27\\")
end

local function has_image_items(items)
  for _, item in ipairs(items or {}) do
    if item.type == "image/png" or item.type == "image/jpeg" or item.type == "image/jpg" then
      return true
    end
  end
  return false
end

local function pane_size_cols_rows()
  if not tmux_available() or not state.pane_id then
    return nil, nil
  end
  local out = vim.fn.systemlist({
    "tmux",
    "display-message",
    "-t",
    state.pane_id,
    "-p",
    "#{pane_width} #{pane_height}",
  })
  if vim.v.shell_error ~= 0 or not out or not out[1] then
    return nil, nil
  end
  local w, h = out[1]:match("^(%d+)%s+(%d+)$")
  return tonumber(w), tonumber(h)
end

local function record_history(label, path, width, height)
  if not path or path == "" then
    return
  end
  table.insert(state.history, { label = label or "Image", path = path, width = width, height = height })
  state.page_index = #state.history
end

local function compute_cols_rows(meta)
  local config = require("neo_notebooks").config
  local cols = config.image_default_cols or 12
  local rows = config.image_default_rows or 6
  if config.image_size_mode == "pane" then
    local pane_w, pane_h = pane_size_cols_rows()
    if pane_w and pane_h then
      local margin_cols = tonumber(config.image_pane_margin_cols) or 0
      local margin_rows = tonumber(config.image_pane_margin_rows) or 0
      cols = math.max(1, pane_w - margin_cols)
      rows = math.max(1, pane_h - margin_rows)
      -- Clamp to pane bounds to avoid overlap at the split boundary.
      cols = math.max(1, math.min(cols, pane_w - 1))
      rows = math.max(1, math.min(rows, pane_h - 1))
      if config.image_pane_preserve_aspect and meta and meta.width and meta.height then
        local aspect = meta.height / math.max(1, meta.width)
        local cell_ratio = tonumber(config.image_pane_cell_ratio) or 2.0
        local calc_rows = math.max(1, math.floor(cols * aspect / math.max(0.1, cell_ratio)))
        if calc_rows > rows then
          rows = rows
          cols = math.max(1, math.floor((rows * cell_ratio) / math.max(0.01, aspect)))
        else
          rows = calc_rows
        end
      end
    end
  end
  return cols, rows
end
sync_size_index = function()
  local config = require("neo_notebooks").config
  local sizes = config.image_pane_sizes or { 25, 33, 50 }
  local percent = tonumber(config.image_pane_tmux_percent) or tonumber(sizes[1]) or 25
  for i, v in ipairs(sizes) do
    if tonumber(v) == percent then
      state.size_index = i
      return
    end
  end
  state.size_index = 1
end

function M.clear()
  if not tty_path() then
    return
  end
  -- Clear images then clear screen without wiping scrollback.
  send_kitty_delete_all()
  send("\27[2J\27[H")
end

local function render_entry(entry)
  if not entry or not entry.path then
    return false
  end
  local cols, rows = compute_cols_rows({ width = entry.width, height = entry.height })
  local origin = vim.env.TMUX_PANE
  if vim.env.TMUX and state.pane_id and origin then
    vim.fn.system({ "tmux", "select-pane", "-t", state.pane_id })
  end
  M.clear()
  send(string.format("\r\n[%s]\r\n", entry.label or "Image"))
  local raw = read_file_bytes(entry.path)
  if raw then
    local b64 = vim.base64.encode(raw)
    local params = {
      "a=T",
      "f=100",
      "c=" .. tostring(cols),
      "r=" .. tostring(rows),
      "C=1",
    }
    local payload = kitty_payload(b64, params)
    if payload then
      send_kitty(payload)
    end
  end
  if vim.env.TMUX and state.pane_id and origin then
    vim.fn.system({ "tmux", "select-pane", "-t", origin })
  end
  return true
end

local function render_current_page()
  if #state.history == 0 then
    return false
  end
  local idx = math.max(1, math.min(state.page_index, #state.history))
  state.page_index = idx
  return render_entry(state.history[idx])
end

function M.reset()
  state.tty = nil
  state.pane_id = nil
  state.history = {}
  state.size_index = 1
  state.disabled = false
  state.page_index = 0
end

function M.is_open()
  if state.disabled then
    return false
  end
  if state.pane_id then
    return pane_exists()
  end
  return state.tty ~= nil
end

function M.open()
  return ensure_tty(true)
end

function M.can_render()
  if not kitty_supported() then
    return false
  end
  if tty_path() then
    return true
  end
  return tmux_available()
end

function M.render_items(cell, items)
  if not kitty_supported() then
    return false
  end
  if not has_image_items(items) then
    if vim.g.neo_notebooks_debug_output then
      vim.notify("NeoNotebook: no image items to render", vim.log.levels.INFO)
    end
    return false
  end
  local rendered = false
  local has_pane = ensure_tty(false) ~= nil and M.is_open()
  if vim.g.neo_notebooks_debug_output then
    vim.notify("NeoNotebook: rendering images to " .. tostring(tty_path()), vim.log.levels.INFO)
  end
  local config = require("neo_notebooks").config
  local spacing = tonumber(config.image_pane_spacing_lines) or 1
  local pane_mode = config.image_pane_mode or "page"
  local origin = vim.env.TMUX_PANE
  if has_pane and vim.env.TMUX and state.pane_id and origin then
    vim.fn.system({ "tmux", "select-pane", "-t", state.pane_id })
  end
  local paths = {}
  local img_index = 0
  for _, item in ipairs(items or {}) do
    if (item.type == "image/png" or item.type == "image/jpeg" or item.type == "image/jpg") and item.data then
      img_index = img_index + 1
      local ext = item.type == "image/png" and "png" or "jpg"
      local path = write_temp_image(item.data, ext, cell.id or "cell", img_index)
      local w, h = nil, nil
      if path then
        w, h = read_image_size(path)
      end
      if path then
        table.insert(paths, path)
        record_history(string.format("Cell %s", tostring(cell.id or "?")), path, w, h)
      end
      if has_pane and pane_mode ~= "page" then
        send(string.format("\r\n[Cell %s]\r\n", tostring(cell.id or "?")))
      end
      if has_pane and path and pane_mode ~= "page" then
        local cols, rows = compute_cols_rows({ width = w, height = h })
        local params = {
          "a=T",
          "f=100",
          "c=" .. tostring(cols),
          "r=" .. tostring(rows),
          "C=1",
        }
        local raw = read_file_bytes(path)
        if raw then
          local b64 = vim.base64.encode(raw)
          local payload = kitty_payload(b64, params)
          if payload then
            send_kitty(payload)
            rendered = true
          end
        end
        -- Advance cursor by image height so subsequent renders don't overlap.
        send(string.rep("\r\n", rows + spacing))
      end
    end
  end
  if has_pane and pane_mode == "page" and #state.history > 0 then
    rendered = render_current_page() or rendered
  end
  if has_pane and vim.env.TMUX and state.pane_id and origin then
    vim.fn.system({ "tmux", "select-pane", "-t", origin })
  end
  return { paths = paths, rendered = rendered }
end

function M.render_file(path, cell_label)
  if not kitty_supported() then
    return false
  end
  if not ensure_tty(false) then
    return false
  end
  local raw = read_file_bytes(path)
  if not raw then
    return false
  end
  local w, h = read_image_size(path)
  record_history(cell_label or "Image Test", path, w, h)
  local config = require("neo_notebooks").config
  if (config.image_pane_mode or "page") == "page" then
    if ensure_tty(false) then
      return render_current_page()
    end
    return false
  end
  local origin = vim.env.TMUX_PANE
  if vim.env.TMUX and state.pane_id and origin then
    vim.fn.system({ "tmux", "select-pane", "-t", state.pane_id })
  end
  send(string.format("\r\n[%s]\r\n", cell_label or "Image Test"))
  local cols, rows = compute_cols_rows({ width = w, height = h })
  local spacing = tonumber(config.image_pane_spacing_lines) or 1
  local params = {
    "a=T",
    "f=100",
    "c=" .. tostring(cols),
    "r=" .. tostring(rows),
    "C=1",
  }
  local b64 = vim.base64.encode(raw)
  local payload = kitty_payload(b64, params)
  if payload then
    send_kitty(payload)
  end
  -- Advance cursor by image height so subsequent renders don't overlap.
  send(string.rep("\r\n", rows + spacing))
  if vim.env.TMUX and state.pane_id and origin then
    vim.fn.system({ "tmux", "select-pane", "-t", origin })
  end
  return true
end

function M.redraw()
  if not ensure_tty(false) then
    return
  end
  local config = require("neo_notebooks").config
  if (config.image_pane_mode or "page") == "page" then
    render_current_page()
    return
  end
  M.clear()
  if #state.history == 0 then
    return
  end
  local cols, rows = compute_cols_rows()
  local spacing = tonumber(config.image_pane_spacing_lines) or 1
  local origin = vim.env.TMUX_PANE
  if vim.env.TMUX and state.pane_id and origin then
    vim.fn.system({ "tmux", "select-pane", "-t", state.pane_id })
  end
  for _, entry in ipairs(state.history) do
    send(string.format("\r\n[%s]\r\n", entry.label or "Image"))
    local path = entry.path
    local params = {
      "a=T",
      "f=100",
      "c=" .. tostring(cols),
      "r=" .. tostring(rows),
      "C=1",
    }
    if path then
      local raw = read_file_bytes(path)
      if raw then
        local b64 = vim.base64.encode(raw)
        local payload = kitty_payload(b64, params)
        if payload then
          send_kitty(payload)
        end
      end
    end
    send(string.rep("\r\n", rows + spacing))
  end
  if vim.env.TMUX and state.pane_id and origin then
    vim.fn.system({ "tmux", "select-pane", "-t", origin })
  end
end

function M.toggle_size()
  if not tmux_available() then
    return
  end
  if not ensure_tty(true) then
    return
  end
  if not state.pane_id then
    return
  end
  local config = require("neo_notebooks").config
  local sizes = config.image_pane_sizes or { 25, 33, 50 }
  if #sizes == 0 then
    sizes = { 25, 33, 50 }
  end
  state.size_index = state.size_index + 1
  if state.size_index > #sizes then
    state.size_index = 1
  end
  local percent = tonumber(sizes[state.size_index]) or 25
  local width_out = vim.fn.systemlist({ "tmux", "display-message", "-t", state.pane_id, "-p", "#{window_width}" })
  local win_width = tonumber(width_out and width_out[1]) or 0
  if win_width > 0 then
    local cols = math.max(20, math.floor(win_width * (percent / 100)))
    vim.fn.system({ "tmux", "resize-pane", "-t", state.pane_id, "-x", tostring(cols) })
    -- Give tmux a moment to apply the resize before redrawing.
    vim.defer_fn(function()
      M.redraw()
    end, 50)
  end
end

function M.collapse()
  if not tmux_available() then
    return
  end
  if state.pane_id and pane_exists() then
    local origin = vim.env.TMUX_PANE
    if origin then
      vim.fn.system({ "tmux", "select-pane", "-t", state.pane_id })
    end
    send_kitty_delete_all()
    M.clear()
    vim.fn.system({ "tmux", "kill-pane", "-t", state.pane_id })
    if origin then
      vim.fn.system({ "tmux", "select-pane", "-t", origin })
    end
    state.tty = nil
    state.pane_id = nil
    state.size_index = 1
    state.disabled = true
    return
  end
  -- If pane is closed, reopen and redraw from history.
  state.disabled = false
  if ensure_tty(true) then
    M.redraw()
  end
end

function M.next()
  if #state.history == 0 then
    return
  end
  state.page_index = math.min(#state.history, state.page_index + 1)
  if ensure_tty(true) then
    render_current_page()
  end
end

function M.prev()
  if #state.history == 0 then
    return
  end
  state.page_index = math.max(1, state.page_index - 1)
  if ensure_tty(true) then
    render_current_page()
  end
end

function M.statusline()
  local config = require("neo_notebooks").config
  if not state.pane_id then
    return ""
  end
  local sizes = config.image_pane_sizes or { 25, 33, 50 }
  local size = sizes[state.size_index] or config.image_pane_tmux_percent or ""
  if size == "" then
    return ""
  end
  if (config.image_pane_mode or "page") == "page" and #state.history > 0 then
    return string.format("IP:%s%% [%d/%d]", tostring(size), state.page_index, #state.history)
  end
  return string.format("IP:%s%%", tostring(size))
end

return M
