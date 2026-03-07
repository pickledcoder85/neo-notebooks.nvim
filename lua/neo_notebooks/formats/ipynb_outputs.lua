local M = {}

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

function M.outputs_to_items(outputs)
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

function M.items_to_outputs(items)
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

return M
