local cells = require("neo_notebooks.cells")
local config = require("neo_notebooks").config
local spinner = require("neo_notebooks.spinner")
local output = require("neo_notebooks.output")

local M = {}

local sessions = {}

local function get_hash_store(bufnr)
  local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, "neo_notebooks_exec_hashes")
  if ok and type(value) == "table" then
    return value
  end
  local empty = {}
  vim.api.nvim_buf_set_var(bufnr, "neo_notebooks_exec_hashes", empty)
  return empty
end

local function set_hash_store(bufnr, store)
  vim.api.nvim_buf_set_var(bufnr, "neo_notebooks_exec_hashes", store)
end
local request_id = 0

local PY_SERVER = [[
import sys, json, traceback, io, contextlib, ast, base64, os

try:
    from rich.console import Console
    from rich.table import Table
    RICH_AVAILABLE = True
except Exception:
    Console = None
    Table = None
    RICH_AVAILABLE = False

globals_dict = {"__name__": "__main__"}
globals_dict["__neo_notebooks_rich"] = True
globals_dict["__neo_notebooks_rich_max_rows"] = 20
globals_dict["__neo_notebooks_rich_max_cols"] = 20
globals_dict["__neo_notebooks_rich_tip_shown"] = False
globals_dict["__neo_notebooks_debug_ansi"] = False
globals_dict["__neo_notebooks_force_rich_console"] = True
globals_dict["__neo_notebooks_show_called"] = False
globals_dict["__neo_notebooks_mpl_patched"] = False

def neo_rich(enable=None):
    if enable is None:
        return globals_dict.get("__neo_notebooks_rich", True)
    globals_dict["__neo_notebooks_rich"] = bool(enable)
    return globals_dict["__neo_notebooks_rich"]

globals_dict["neo_rich"] = neo_rich

def neo_ansi_debug(enable=None):
    if enable is None:
        return globals_dict.get("__neo_notebooks_debug_ansi", False)
    globals_dict["__neo_notebooks_debug_ansi"] = bool(enable)
    return globals_dict["__neo_notebooks_debug_ansi"]

globals_dict["neo_ansi_debug"] = neo_ansi_debug

def neo_force_rich_console(enable=None):
    if enable is None:
        return globals_dict.get("__neo_notebooks_force_rich_console", True)
    globals_dict["__neo_notebooks_force_rich_console"] = bool(enable)
    return globals_dict["__neo_notebooks_force_rich_console"]

globals_dict["neo_force_rich_console"] = neo_force_rich_console

def _maybe_patch_rich_console():
    if not globals_dict.get("__neo_notebooks_force_rich_console", True):
        return
    if not RICH_AVAILABLE:
        return
    try:
        import rich.console as _rc
    except Exception:
        return
    if getattr(_rc, "__neo_notebooks_patched", False):
        return
    _orig_console = _rc.Console

    def _patched_console(*args, **kwargs):
        kwargs.setdefault("force_terminal", True)
        kwargs.setdefault("color_system", "standard")
        kwargs.setdefault("no_color", False)
        return _orig_console(*args, **kwargs)

    _rc.Console = _patched_console
    _rc.__neo_notebooks_patched = True

# Ensure a non-GUI backend when configured (prevents blocking show() calls).
_mpl_backend = os.environ.get("MPLBACKEND")
if _mpl_backend:
    try:
        import matplotlib
        matplotlib.use(_mpl_backend)
    except Exception:
        pass

def _maybe_patch_matplotlib_show():
    if globals_dict.get("__neo_notebooks_mpl_patched", False):
        return
    try:
        import matplotlib.pyplot as plt
    except Exception:
        return
    def _neo_show(*args, **kwargs):
        globals_dict["__neo_notebooks_show_called"] = True
        return None
    try:
        plt.show = _neo_show
        globals_dict["__neo_notebooks_mpl_patched"] = True
    except Exception:
        return

# Ensure a non-GUI backend when configured (prevents blocking show() calls).
_mpl_backend = os.environ.get("MPLBACKEND")
if _mpl_backend:
    try:
        import matplotlib
        matplotlib.use(_mpl_backend)
    except Exception:
        pass

def _capture_matplotlib_png():
    try:
        import matplotlib.pyplot as plt
    except Exception:
        return None
    try:
        fignums = plt.get_fignums()
    except Exception:
        return None
    if not fignums:
        return None
    try:
        fig = plt.figure(fignums[-1])
        if fig is None:
            return None
        buf = io.BytesIO()
        fig.savefig(buf, format="png", bbox_inches="tight")
        png = buf.getvalue()
        if not png:
            return None
        width, height = fig.canvas.get_width_height()
        return {
            "type": "image/png",
            "data": base64.b64encode(png).decode("ascii"),
            "meta": { "width": width, "height": height },
        }
    except Exception:
        return None

def _is_pandas_obj(value):
    mod = getattr(value.__class__, "__module__", "")
    return mod.startswith("pandas")

def _render_pandas_table(value, out_buf):
    try:
        import pandas as pd
    except Exception:
        return False

    if isinstance(value, pd.Series):
        df = value.to_frame()
    elif isinstance(value, pd.DataFrame):
        df = value
    else:
        return False

    max_rows = int(globals_dict.get("__neo_notebooks_rich_max_rows", 20))
    max_cols = int(globals_dict.get("__neo_notebooks_rich_max_cols", 20))

    df_view = df.iloc[:max_rows, :max_cols]
    table = Table(
        show_header=True,
        header_style="bold cyan",
        title_style="bold magenta",
        border_style="bright_magenta",
    )
    table.add_column("")
    for col in df_view.columns:
        table.add_column(str(col), style="bright_yellow")

    for idx, row in df_view.iterrows():
        cells = [str(idx)]
        for col in df_view.columns:
            cells.append(str(row[col]))
        table.add_row(*cells)

    console = Console(file=out_buf, force_terminal=True, color_system="standard")
    console.print(table)
    return True

def handle(obj):
    code = obj.get("code", "")
    out_buf = io.StringIO()
    err_buf = io.StringIO()
    _maybe_patch_rich_console()
    globals_dict["__neo_notebooks_show_called"] = False
    _maybe_patch_matplotlib_show()
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
                    use_rich = globals_dict.get("__neo_notebooks_rich", True)
                    if use_rich and not RICH_AVAILABLE and not globals_dict.get("__neo_notebooks_rich_tip_shown", False):
                        out_buf.write("[neo_notebooks] Tip: install 'rich' for nicer output\n")
                        globals_dict["__neo_notebooks_rich_tip_shown"] = True
                    if use_rich and RICH_AVAILABLE and _is_pandas_obj(value):
                        rendered = _render_pandas_table(value, out_buf)
                        if not rendered:
                            print(repr(value))
                    elif use_rich and RICH_AVAILABLE:
                        console = Console(file=out_buf, force_terminal=True, color_system="standard")
                        console.print(value)
                    else:
                        if _is_pandas_obj(value):
                            try:
                                print(value.to_string())
                            except Exception:
                                print(repr(value))
                        else:
                            print(repr(value))
            else:
                exec(compile(tree, "<cell>", "exec"), globals_dict)
        except KeyboardInterrupt:
            ok = False
            trace = ""
            interrupted = True
        except Exception:
            ok = False
            trace = traceback.format_exc()
            interrupted = False
    items = []
    out_val = out_buf.getvalue()
    err_val = err_buf.getvalue()
    trace_val = trace
    if out_val:
        items.append({ "type": "text/plain", "data": out_val })
    if err_val:
        items.append({ "type": "text/plain", "data": err_val, "meta": { "stream": "stderr" } })
    if trace_val:
        items.append({ "type": "text/plain", "data": trace_val, "meta": { "stream": "traceback" } })
    png_item = None
    if ok:
        png_item = _capture_matplotlib_png()
    if png_item:
        items.append(png_item)
    resp = {
        "id": obj.get("id"),
        "ok": ok,
        "out": out_val,
        "err": err_val,
        "trace": trace_val,
        "items": items,
        "interrupted": interrupted if 'interrupted' in locals() else False,
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

local function resolve_bufnr(bufnr)
  if not bufnr or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
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

local function format_payload(resp)
  local lines = format_output(resp)
  if resp.items and type(resp.items) == "table" then
    return { lines = lines, items = resp.items }
  end
  return lines
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
  local trace = resp.trace or ""
  local err = resp.err or ""
  if resp.interrupted == true or (pending.interrupted and (trace:find("KeyboardInterrupt", 1, true) or err:find("KeyboardInterrupt", 1, true))) then
    local resolved = pending.cell_id
    if not resolved and pending.line then
      local index = require("neo_notebooks.index")
      local cell = index.find_cell(pending.bufnr, pending.line)
      if cell then
        resolved = cell.id
      end
    end
    local newer = false
    if resolved and pending.gen and session.cell_generation then
      local current = session.cell_generation[resolved]
      if current and current ~= pending.gen then
        newer = true
      end
    end
    if not newer then
      spinner.stop(pending.bufnr, resolved)
      if resolved then
        output.clear_by_id(pending.bufnr, resolved)
      end
    end
    session.pending[id] = nil
    if session.active_request_id == id then
      session.active_request_id = nil
    end
    if session.drain_queue then
      session.drain_queue()
    end
    return
  end
  local duration_ms = nil
  if pending.started_at then
    duration_ms = (vim.loop.hrtime() - pending.started_at) / 1e6
  end
  local resolved_cell_id = pending.cell_id
  if not resolved_cell_id and pending.line then
    local index = require("neo_notebooks.index")
    local cell = index.find_cell(pending.bufnr, pending.line)
    if cell then
      resolved_cell_id = cell.id
      pending.cell_id = resolved_cell_id
    end
  end
  if duration_ms then
    local timing_id = resolved_cell_id
    if timing_id then
      output.set_timing(pending.bufnr, timing_id, duration_ms)
    end
  end
  spinner.stop(pending.bufnr, resolved_cell_id)
  session.pending[id] = nil
  if resolved_cell_id and pending.code_hash then
    local store = get_hash_store(pending.bufnr)
    store[resolved_cell_id] = pending.code_hash
    set_hash_store(pending.bufnr, store)
  end
  local output = format_payload(resp)
  if pending.on_output then
    if vim.g.neo_notebooks_debug_output then
      vim.schedule(function()
        vim.notify("exec: on_output callback", vim.log.levels.INFO)
      end)
    end
    vim.schedule(function()
      pending.on_output(output, resolved_cell_id, duration_ms)
    end)
  else
    if type(output) == "table" and output.lines then
      open_output_window(output.lines)
    else
      open_output_window(output)
    end
  end
  if session.active_request_id == id then
    session.active_request_id = nil
  end
  if session.drain_queue then
    session.drain_queue()
  end
end

local function ensure_session(bufnr)
  bufnr = resolve_bufnr(bufnr)
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
    queue = {},
    active_request_id = nil,
    drain_queue = nil,
    cell_generation = {},
  }

  session.job = vim.fn.jobstart(cmd, {
    env = (function()
      local env = {}
      if config.mpl_backend and config.mpl_backend ~= "" then
        env.MPLBACKEND = config.mpl_backend
      end
      return env
    end)(),
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
  bufnr = resolve_bufnr(bufnr)
  local session = sessions[bufnr]
  if not session then
    return
  end
  spinner.stop_all(bufnr)
  if is_job_alive(session.job) then
    vim.fn.jobstop(session.job)
  end
  sessions[bufnr] = nil
end

local function build_request(bufnr, line, opts)
  opts = opts or {}
  bufnr = resolve_bufnr(bufnr)
  local code, err = cells.get_cell_code(bufnr, line)
  if err then
    vim.notify(err, vim.log.levels.WARN)
    return nil
  end

  if code == nil or code == "" then
    vim.notify("Cell is empty", vim.log.levels.INFO)
    return nil
  end

  local cell_id = opts.cell_id
  if not cell_id then
    local index = require("neo_notebooks.index")
    local cell = index.find_cell(bufnr, line)
    if cell then
      cell_id = cell.id
    end
  end

  return {
    bufnr = bufnr,
    line = line,
    code = code,
    code_hash = vim.fn.sha256(code),
    on_output = opts.on_output,
    cell_id = cell_id,
  }
end

local function dispatch_request(session, req)
  request_id = request_id + 1
  local id = request_id

  local payload = vim.fn.json_encode({ id = id, code = req.code })
  session.pending[id] = {
    bufnr = req.bufnr,
    on_output = req.on_output,
    cell_id = req.cell_id,
    line = req.line,
    code_hash = req.code_hash,
    started_at = vim.loop.hrtime(),
  }
  if req.cell_id then
    local gen = (session.cell_generation[req.cell_id] or 0) + 1
    session.cell_generation[req.cell_id] = gen
    session.pending[id].gen = gen
  end
  session.active_request_id = id
  if req.cell_id then
    spinner.start(req.bufnr, req.cell_id, req.line)
  end
  if req.cell_id and req.on_output then
    local index = require("neo_notebooks.index")
    local cell = index.get_by_id(req.bufnr, req.cell_id) or index.find_cell(req.bufnr, req.line)
    if cell then
      output.show_inline(req.bufnr, {
        id = cell.id,
        start = cell.start,
        finish = cell.finish,
        type = cell.type,
      }, { "cell executing..." }, { executing = true })
    end
  end
  vim.fn.chansend(session.job, payload .. "\n")
end

local function make_queue_drainer(session)
  return function()
    if session.active_request_id then
      return
    end
    while #session.queue > 0 do
      local req = table.remove(session.queue, 1)
      if req and vim.api.nvim_buf_is_valid(req.bufnr) then
        dispatch_request(session, req)
        return
      end
    end
  end
end

function M.enqueue_cell(bufnr, line, opts)
  bufnr = resolve_bufnr(bufnr)
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1
  opts = opts or {}
  local req = build_request(bufnr, line, opts)
  if not req then
    return
  end

  local session = ensure_session(bufnr)
  if not session then
    return
  end
  local config = require("neo_notebooks").config
  if req.cell_id and config.skip_unchanged_rerun then
    local store = get_hash_store(bufnr)
    if store[req.cell_id] and store[req.cell_id] == req.code_hash then
      return
    end
  end
  if req.cell_id and config.interrupt_on_rerun then
    local active_id = session.active_request_id
    local pending = active_id and session.pending and session.pending[active_id] or nil
    if pending and pending.cell_id == req.cell_id then
      if not config.skip_unchanged_rerun or pending.code_hash ~= req.code_hash then
        local pid = vim.fn.jobpid(session.job)
        if pid and pid > 0 then
          pcall(vim.loop.kill, pid, "sigint")
        end
        spinner.stop(bufnr, req.cell_id)
        pending.interrupted = true
        session.active_request_id = nil
      end
    end
  end
  if not session.drain_queue then
    session.drain_queue = make_queue_drainer(session)
  end
  local pushed = false
  if config.interrupt_on_rerun and session.active_request_id == nil then
    table.insert(session.queue, 1, req)
    pushed = true
  end
  if not pushed then
    table.insert(session.queue, req)
  end
  session.drain_queue()
end

function M.run_cell(bufnr, line, opts)
  M.enqueue_cell(bufnr, line, opts)
end

function M.clear_cell_hash(bufnr, cell_id)
  bufnr = resolve_bufnr(bufnr)
  if not cell_id then
    return
  end
  local store = get_hash_store(bufnr)
  store[cell_id] = nil
  set_hash_store(bufnr, store)
end

function M.clear_all_hashes(bufnr)
  bufnr = resolve_bufnr(bufnr)
  set_hash_store(bufnr, {})
end

function M._get_hash_store_for_test(bufnr)
  bufnr = resolve_bufnr(bufnr)
  return get_hash_store(bufnr)
end

function M._set_hash_store_for_test(bufnr, store)
  bufnr = resolve_bufnr(bufnr)
  set_hash_store(bufnr, store or {})
end

return M
