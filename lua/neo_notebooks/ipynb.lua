local cells = require("neo_notebooks.cells")

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
  local lines = {}

  for _, cell in ipairs(cells_in) do
    local ctype = cell.cell_type or "code"
    local marker = "# %% [" .. ctype .. "]"
    table.insert(lines, marker)

    local src = cell.source or {}
    for _, line in ipairs(normalize_lines(src)) do
      table.insert(lines, line)
    end

    table.insert(lines, "")
  end

  if #lines == 0 then
    lines = { "# %% [markdown]", "" }
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return true
end

function M.export_ipynb(path, bufnr)
  bufnr = bufnr or 0
  local list = cells.get_cells(bufnr)
  local cells_out = {}

  for _, cell in ipairs(list) do
    local body = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
    local src = {}
    for _, line in ipairs(body) do
      table.insert(src, line .. "\n")
    end

    table.insert(cells_out, {
      cell_type = cell.type,
      metadata = {},
      source = src,
    })
  end

  local doc = {
    cells = cells_out,
    metadata = {
      language_info = { name = "python" },
    },
    nbformat = 4,
    nbformat_minor = 5,
  }

  local json = vim.fn.json_encode(doc)
  return write_file(path, json)
end

function M.open_ipynb(path)
  local existing = vim.fn.bufnr(path)
  if existing ~= -1 then
    local bufnr = existing
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
    vim.api.nvim_set_option_value("filetype", "neo_notebook", { buf = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
    return M.import_ipynb(path, bufnr)
  end
  vim.cmd("enew")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(bufnr, path)
  vim.api.nvim_set_option_value("filetype", "neo_notebook", { buf = bufnr })
  return M.import_ipynb(path, bufnr)
end

return M
