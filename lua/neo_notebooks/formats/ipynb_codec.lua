local M = {}

local function normalize_lines(src)
  local out = {}
  for _, line in ipairs(src or {}) do
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
  local out = vim.deepcopy(lines or {})
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

function M.decode_document(content)
  local ok, doc = pcall(vim.fn.json_decode, content)
  if not ok or type(doc) ~= "table" then
    return nil, "Invalid JSON"
  end
  return doc
end

function M.encode_document(doc)
  local ok, json = pcall(vim.fn.json_encode, doc)
  if not ok then
    return nil, "Failed to encode JSON"
  end
  return json
end

function M.prepare_import_cells(cells_in)
  local out = vim.deepcopy(cells_in or {})
  if #out >= 2 then
    local first = out[1]
    local second = out[2]
    if first and second and first.cell_type == "code" and second.cell_type == "markdown" and source_is_blank(first.source) then
      table.remove(out, 1)
    end
  end
  return out
end

function M.cells_to_buffer_lines(cells_in)
  local lines = {}
  for _, cell in ipairs(cells_in or {}) do
    local ctype = cell.cell_type or "code"
    table.insert(lines, "# %% [" .. ctype .. "]")
    local src = cell.source or {}
    for _, line in ipairs(trim_trailing_blank_lines(normalize_lines(src))) do
      table.insert(lines, line)
    end
    table.insert(lines, "")
  end
  if #lines == 0 then
    lines = { "# %% [markdown]", "" }
  end
  return lines
end

function M.build_export_cells(bufnr, list, idx, state)
  local cells_out = {}
  for _, cell in ipairs(list or {}) do
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
  return cells_out
end

function M.build_document(state, cells_out, is_jupytext, default_jupytext_metadata)
  local metadata = {}
  if type(state.metadata) == "table" then
    metadata = vim.deepcopy(state.metadata)
  end
  metadata = vim.tbl_deep_extend("force", {
    language_info = { name = "python" },
  }, metadata)
  if is_jupytext then
    metadata.jupytext = vim.tbl_deep_extend("force", default_jupytext_metadata(), metadata.jupytext or {})
  end

  return {
    cells = cells_out,
    metadata = metadata,
    nbformat = state.nbformat or 4,
    nbformat_minor = state.nbformat_minor or 5,
  }
end

return M
