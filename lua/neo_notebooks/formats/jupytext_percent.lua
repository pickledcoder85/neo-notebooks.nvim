local M = {}

local function strip_quotes(s)
  if type(s) ~= "string" then
    return s
  end
  if (#s >= 2) and ((s:sub(1, 1) == "'" and s:sub(-1) == "'") or (s:sub(1, 1) == '"' and s:sub(-1) == '"')) then
    return s:sub(2, -2)
  end
  return s
end

function M.default_metadata()
  return {
    formats = "ipynb,py:percent",
    text_representation = {
      extension = ".py",
      format_name = "percent",
      format_version = "1.3",
    },
  }
end

local function parse_header(lines)
  if not lines or #lines == 0 then
    return nil, 1
  end
  if lines[1] ~= "# ---" then
    return nil, 1
  end
  local body = {}
  local end_idx = nil
  for i = 2, #lines do
    if lines[i] == "# ---" then
      end_idx = i
      break
    end
    table.insert(body, lines[i])
  end
  if not end_idx then
    return nil, 1
  end

  local metadata = {}
  local saw_jupytext = false
  local in_jupytext = false
  local in_text_representation = false

  for _, raw in ipairs(body) do
    local line = raw:gsub("^#%s?", "")
    local indent = line:match("^(%s*)") or ""
    local depth = #indent
    local trimmed = vim.trim(line)
    if trimmed ~= "" then
      if trimmed:match("^jupytext:%s*$") then
        saw_jupytext = true
        in_jupytext = true
        in_text_representation = false
        metadata.jupytext = metadata.jupytext or {}
      elseif depth == 0 and trimmed:match("^%w[%w_]*:%s*$") then
        in_jupytext = false
        in_text_representation = false
      elseif in_jupytext and trimmed:match("^text_representation:%s*$") then
        in_text_representation = true
        metadata.jupytext.text_representation = metadata.jupytext.text_representation or {}
      elseif in_jupytext then
        local key, value = trimmed:match("^(%w[%w_]*):%s*(.+)$")
        if key and value then
          value = strip_quotes(vim.trim(value))
          if in_text_representation and depth >= 6 then
            metadata.jupytext.text_representation[key] = value
          elseif key == "formats" then
            metadata.jupytext.formats = value
            in_text_representation = false
          else
            metadata.jupytext[key] = value
          end
        end
      end
    end
  end

  if not saw_jupytext then
    metadata = nil
  else
    metadata.jupytext = vim.tbl_deep_extend("force", M.default_metadata(), metadata.jupytext or {})
  end
  return metadata, end_idx + 1
end

local function parse_percent_cell_type(line)
  if type(line) ~= "string" then
    return nil
  end
  if not line:match("^#%s*%%%%") then
    return nil
  end
  local tag = line:match("%[(.-)%]") or ""
  tag = vim.trim(tag):lower()
  if tag == "markdown" or tag == "md" then
    return "markdown"
  end
  return "code"
end

local function markdown_from_percent_line(line)
  if line == "#" then
    return ""
  end
  if line:sub(1, 2) == "# " then
    return line:sub(3)
  end
  if line:sub(1, 1) == "#" then
    return line:sub(2)
  end
  return line
end

function M.parse(lines)
  local parsed_meta, start_idx = parse_header(lines)
  local cells_out = {}
  local current = nil

  local function flush_current()
    if current then
      table.insert(cells_out, current)
      current = nil
    end
  end

  for i = start_idx, #lines do
    local raw = lines[i]
    local ctype = parse_percent_cell_type(raw)
    if ctype then
      flush_current()
      current = {
        cell_type = ctype,
        source = {},
      }
    else
      if not current then
        if vim.trim(raw or "") == "" then
          goto continue
        end
        current = {
          cell_type = "code",
          source = {},
        }
      end
      local text = raw
      if current.cell_type == "markdown" then
        text = markdown_from_percent_line(raw)
      end
      table.insert(current.source, text)
    end
    ::continue::
  end
  flush_current()

  if #cells_out == 0 then
    cells_out = {
      { cell_type = "markdown", source = { "" } },
    }
  end
  return cells_out, parsed_meta
end

return M
