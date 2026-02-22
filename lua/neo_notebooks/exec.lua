local cells = require("neo_notebooks.cells")
local config = require("neo_notebooks").config

local M = {}

local sessions = {}
local request_id = 0

local PY_SERVER = [[
import sys, json, traceback, io, contextlib, ast

globals_dict = {"__name__": "__main__"}

def handle(obj):
    code = obj.get("code", "")
    out_buf = io.StringIO()
    err_buf = io.StringIO()
    ok = True
    trace = ""
    with contextlib.redirect_stdout(out_buf), contextlib.redirect_stderr(err_buf):
        try:
            tree = ast.parse(code, mode="exec")
            if tree.body and isinstance(tree.body[-1], ast.Expr):
                last_expr = tree.body[-1]
                tree.body = tree.body[:-1]
                if tree.body:
                    exec(compile(tree, "<cell>", "exec"), globals_dict)
                value = eval(compile(ast.Expression(last_expr.value), "<cell>", "eval"), globals_dict)
                if value is not None:
                    print(repr(value))
            else:
                exec(compile(tree, "<cell>", "exec"), globals_dict)
        except Exception:
            ok = False
            trace = traceback.format_exc()
    resp = {
        "id": obj.get("id"),
        "ok": ok,
        "out": out_buf.getvalue(),
        "err": err_buf.getvalue(),
        "trace": trace,
    }
    sys.stdout.write(json.dumps(resp) + "\n")
    sys.stdout.flush()

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        resp = {"id": None, "ok": False, "out": "", "err": "", "trace": "Invalid JSON"}
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()
        continue
    handle(obj)
]]

local function open_output_window(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local width = math.min(vim.o.columns - 4, 120)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.4))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(1, vim.o.lines - height - 4),
    col = math.max(1, vim.o.columns - width - 2),
    width = width,
    height = height,
    style = "minimal",
    border = "single",
  })

  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true })
  return win
end

local function parse_cmd(cmd)
  if type(cmd) == "table" then
    return cmd
  end
  if type(cmd) ~= "string" or cmd == "" then
    return { "python3" }
  end
  if cmd:find("%s") then
    return vim.split(cmd, "%s+")
  end
  return { cmd }
end

local function is_job_alive(job_id)
  if not job_id then
    return false
  end
  local status = vim.fn.jobwait({ job_id }, 0)[1]
  return status == -1
end

local function format_output(resp)
  local output = {}
  local out = resp.out or ""
  local err = resp.err or ""
  local trace = resp.trace or ""

  if out ~= "" then
    for line in out:gmatch("([^\n]*)\n?") do
      if line ~= "" then
        table.insert(output, line)
      end
    end
  end

  if err ~= "" then
    for line in err:gmatch("([^\n]*)\n?") do
      if line ~= "" then
        table.insert(output, line)
      end
    end
  end

  if trace ~= "" then
    for line in trace:gmatch("([^\n]*)\n?") do
      if line ~= "" then
        table.insert(output, line)
      end
    end
  end

  if #output == 0 then
    output = { "(no output)" }
  end

  return output
end

local function handle_response(session, resp)
  if not resp or type(resp) ~= "table" then
    return
  end

  local id = resp.id
  local pending = session.pending[id]
  if not pending then
    return
  end
  session.pending[id] = nil
  local output = format_output(resp)
  if pending.on_output then
    pending.on_output(output)
  else
    open_output_window(output)
  end
end

local function ensure_session(bufnr)
  bufnr = bufnr or 0
  local session = sessions[bufnr]
  if session and is_job_alive(session.job) then
    return session
  end

  local cmd = parse_cmd(config.python_cmd)
  table.insert(cmd, "-u")
  table.insert(cmd, "-c")
  table.insert(cmd, PY_SERVER)

  session = {
    job = nil,
    pending = {},
    partial = "",
  }

  session.job = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, chunk in ipairs(data) do
        if chunk ~= "" then
          local line = session.partial .. chunk
          session.partial = ""
          local ok, decoded = pcall(vim.fn.json_decode, line)
          if ok then
            handle_response(session, decoded)
          else
            session.partial = line
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end
      local output = {}
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(output, line)
        end
      end
      if #output > 0 then
        open_output_window(output)
      end
    end,
  })

  if session.job <= 0 then
    vim.notify("Failed to start Python session", vim.log.levels.ERROR)
    return nil
  end

  sessions[bufnr] = session
  return session
end

function M.stop_session(bufnr)
  bufnr = bufnr or 0
  local session = sessions[bufnr]
  if not session then
    return
  end
  if is_job_alive(session.job) then
    vim.fn.jobstop(session.job)
  end
  sessions[bufnr] = nil
end

function M.run_cell(bufnr, line, opts)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  opts = opts or {}

  local code, err = cells.get_cell_code(bufnr, line)
  if err then
    vim.notify(err, vim.log.levels.WARN)
    return
  end

  if code == nil or code == "" then
    vim.notify("Cell is empty", vim.log.levels.INFO)
    return
  end

  local session = ensure_session(bufnr)
  if not session then
    return
  end

  request_id = request_id + 1
  local payload = vim.fn.json_encode({ id = request_id, code = code })
  session.pending[request_id] = {
    bufnr = bufnr,
    on_output = opts.on_output,
  }
  vim.fn.chansend(session.job, payload .. "\n")
end

return M
