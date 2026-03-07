local cells = require("neo_notebooks.cells")
local index = require("neo_notebooks.index")
local output = require("neo_notebooks.output")

local M = {}

local function read_file(path)
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok then
    return nil, "Failed to read file"
  end
  return table.concat(data, "\n")
end

local function write_file(path, content)
  local ok, err = pcall(vim.fn.writefile, vim.split(content, "\n", { plain = true }), path)
  if not ok then
    return nil, err
  end
  return true
end

local function normalize_lines(src)
  local out = {}
  for _, line in ipairs(src) do
    if line == nil then
      line = ""
    end
    if line:sub(-1) == "\n" then
      line = line:sub(1, -2)
    end
    table.insert(out, line)
  end
  return out
end

local function trim_trailing_blank_lines(lines)
  local out = vim.deepcopy(lines)
  while #out > 0 and out[#out] == "" do
    table.remove(out)
  end
  return out
end

local function source_is_blank(src)
  local normalized = trim_trailing_blank_lines(normalize_lines(src or {}))
  for _, line in ipairs(normalized) do
    if line ~= "" then
      return false
    end
  end
  return true
end

local function get_state(bufnr)
  local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, "neo_notebooks_ipynb_state")
  if ok and type(value) == "table" then
    return value
  end
  local state = {
    nbformat = 4,
    nbformat_minor = 5,
    metadata = {},
    cells = {},
    order = {},
    exec_count = 0,
  }
  pcall(vim.api.nvim_buf_set_var, bufnr, "neo_notebooks_ipynb_state", state)
  return state
end

local function set_state(bufnr, state)
  pcall(vim.api.nvim_buf_set_var, bufnr, "neo_notebooks_ipynb_state", state)
end

local function text_from_field(value)
  if value == nil then
    return ""
  end
  if type(value) == "table" then
    return table.concat(value, "")
  end
  return tostring(value)
end

local function json_from_field(value)
  if value == nil then
    return ""
  end
  if type(value) == "string" then
    return value
  end
  local ok, encoded = pcall(vim.fn.json_encode, value)
  if ok and type(encoded) == "string" then
    return encoded
  end
  return text_from_field(value)
end

local function outputs_to_items(outputs)
  local items = {}
  for _, out in ipairs(outputs or {}) do
    local ot = out.output_type
    if ot == "stream" then
      local text = text_from_field(out.text)
      if text ~= "" then
        table.insert(items, { type = "text/plain", data = text, meta = { stream = out.name or "stdout" } })
      end
    elseif ot == "error" then
      local tb = out.traceback
      local text = text_from_field(tb)
      if text ~= "" then
        table.insert(items, { type = "text/plain", data = text, meta = { stream = "traceback" } })
      end
    elseif ot == "display_data" or ot == "execute_result" then
      local data = out.data or {}
      local meta = out.metadata or {}
      local has_structured_text = data["text/html"] ~= nil or data["application/json"] ~= nil
      local function push(mime, val)
        if val == nil then
          return
        end
        local text = text_from_field(val)
        if text ~= "" then
          table.insert(items, { type = mime, data = text, meta = meta })
        end
      end
      push("image/png", data["image/png"])
      push("image/jpeg", data["image/jpeg"] or data["image/jpg"])
      push("text/html", data["text/html"])
      local json_text = json_from_field(data["application/json"])
      if json_text ~= "" then
        table.insert(items, { type = "application/json", data = json_text, meta = meta })
      end
      if not has_structured_text then
        push("text/plain", data["text/plain"])
      end
    end
  end
  return items
end

local function split_lines_keep_newline(text)
  if text == nil or text == "" then
    return { "" }
  end
  local out = {}
  for line in tostring(text):gmatch("([^\n]*\n?)") do
    if line == "" then
      break
    end
    table.insert(out, line)
  end
  return out
end

local function items_to_outputs(items)
  local outputs = {}
  for _, item in ipairs(items or {}) do
    local kind = item.type or "text/plain"
    local data = item.data or ""
    local meta = item.meta or {}
    if kind == "text/plain" then
      local stream = meta.stream
      if stream == "traceback" then
        table.insert(outputs, {
          output_type = "error",
          ename = meta.ename or "Error",
          evalue = meta.evalue or "",
          traceback = split_lines_keep_newline(data),
        })
      else
        table.insert(outputs, {
          output_type = "stream",
          name = stream == "stderr" and "stderr" or "stdout",
          text = data,
        })
      end
    elseif kind == "image/png" or kind == "image/jpeg" or kind == "image/jpg" then
      local mime = kind == "image/jpg" and "image/jpeg" or kind
      table.insert(outputs, {
        output_type = "display_data",
        data = { [mime] = data },
        metadata = meta,
      })
    else
      table.insert(outputs, {
        output_type = "display_data",
        data = { [kind] = data },
        metadata = meta,
      })
    end
  end
  return outputs
end

function M.import_ipynb(path, bufnr)
  bufnr = bufnr or 0
  local content, err = read_file(path)
  if not content then
    return nil, err
  end

  local ok, doc = pcall(vim.fn.json_decode, content)
  if not ok or type(doc) ~= "table" then
    return nil, "Invalid JSON"
  end

  local cells_in = doc.cells or {}
  if #cells_in >= 2 then
    local first = cells_in[1]
    local second = cells_in[2]
    if first and second and first.cell_type == "code" and second.cell_type == "markdown" and source_is_blank(first.source) then
      table.remove(cells_in, 1)
    end
  end
  local lines = {}

  for _, cell in ipairs(cells_in) do
    local ctype = cell.cell_type or "code"
    local marker = "# %% [" .. ctype .. "]"
    table.insert(lines, marker)

    local src = cell.source or {}
    for _, line in ipairs(trim_trailing_blank_lines(normalize_lines(src))) do
      table.insert(lines, line)
    end

    table.insert(lines, "")
  end

  if #lines == 0 then
    lines = { "# %% [markdown]", "" }
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local state = get_state(bufnr)
  state.nbformat = doc.nbformat or 4
  state.nbformat_minor = doc.nbformat_minor or 5
  state.metadata = doc.metadata or {}
  state.cells = {}
  state.order = {}
  state.exec_count = 0

  local idx = index.rebuild(bufnr)
  for i, cell in ipairs(cells_in) do
    local entry = idx.list[i]
    if entry then
      local cell_id = entry.id
      local exec_count = cell.execution_count
      if type(exec_count) == "number" then
        state.exec_count = math.max(state.exec_count, exec_count)
      end
      state.cells[cell_id] = {
        cell_type = cell.cell_type or entry.type,
        metadata = cell.metadata or {},
        attachments = cell.attachments or {},
        outputs = cell.outputs or {},
        execution_count = exec_count,
      }
      table.insert(state.order, cell_id)
    end
  end
  set_state(bufnr, state)

  output.clear_all(bufnr)
  for _, entry in ipairs(idx.list) do
    local stored = state.cells[entry.id]
    if stored and stored.outputs and entry.type == "code" then
      local items = outputs_to_items(stored.outputs)
      if #items > 0 then
        output.show_payload(bufnr, {
          id = entry.id,
          start = entry.start,
          finish = entry.finish,
          type = entry.type,
        }, { items = items }, {})
      end
    end
  end
  return true
end

function M.export_ipynb(path, bufnr)
  bufnr = bufnr or 0
  local list = cells.get_cells(bufnr)
  local idx = index.rebuild(bufnr)
  local state = get_state(bufnr)
  local cells_out = {}

  for _, cell in ipairs(list) do
    local body = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
    body = trim_trailing_blank_lines(body)
    local src = {}
    for _, line in ipairs(body) do
      table.insert(src, line .. "\n")
    end

    local entry = idx.list[#cells_out + 1]
    local cell_id = entry and entry.id
    local stored = cell_id and state.cells[cell_id] or nil
    local metadata = stored and stored.metadata or {}
    local attachments = stored and stored.attachments or {}
    local outputs = stored and stored.outputs or {}
    local exec_count = stored and stored.execution_count or nil
    local cell_out = {
      cell_type = cell.type,
      metadata = metadata,
      source = src,
    }
    if cell.type == "markdown" then
      if attachments and next(attachments) ~= nil then
        cell_out.attachments = attachments
      end
    else
      cell_out.outputs = outputs or {}
      cell_out.execution_count = exec_count
    end
    table.insert(cells_out, cell_out)
  end

  local doc = {
    cells = cells_out,
    metadata = state.metadata or {
      language_info = { name = "python" },
    },
    nbformat = state.nbformat or 4,
    nbformat_minor = state.nbformat_minor or 5,
  }

  local json = vim.fn.json_encode(doc)
  return write_file(path, json)
end

function M.update_cell_output(bufnr, cell_id, payload)
  bufnr = bufnr or 0
  if not cell_id or not payload or type(payload) ~= "table" then
    return
  end
  local state = get_state(bufnr)
  local existing = state.cells[cell_id] or {}
  if payload.items then
    existing.outputs = items_to_outputs(payload.items)
    state.exec_count = (state.exec_count or 0) + 1
    existing.execution_count = state.exec_count
  end
  state.cells[cell_id] = existing
  set_state(bufnr, state)
end

function M.open_ipynb(path)
  local existing = vim.fn.bufnr(path)
  if existing ~= -1 then
    local bufnr = existing
    vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.b[bufnr].neo_notebooks_enabled = true
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("setfiletype python")
    end)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    local ok, err = M.import_ipynb(path, bufnr)
    return ok, err, bufnr
  end
  vim.cmd("enew")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(bufnr, path)
  vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
  vim.b[bufnr].neo_notebooks_enabled = true
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("setfiletype python")
  end)
  local ok, err = M.import_ipynb(path, bufnr)
  return ok, err, bufnr
end

return M
