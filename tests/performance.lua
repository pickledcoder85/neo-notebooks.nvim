local t = require('tests._helpers')
t.setup()

local ok = t.ok
local with_buf = t.with_buf

local index = require('neo_notebooks.index')
local render = require('neo_notebooks.render')
local ipynb = require('neo_notebooks.ipynb')
local exec = require('neo_notebooks.exec')

local fixture_root = vim.fn.getcwd() .. '/tests/fixtures/perf'

local function now_ms()
  return vim.loop.hrtime() / 1e6
end

local function timed(fn)
  local start = now_ms()
  local result = { pcall(fn) }
  local elapsed = now_ms() - start
  local ok_call = table.remove(result, 1)
  return ok_call, elapsed, unpack(result)
end

local function assert_budget(label, elapsed_ms, max_ms)
  ok(elapsed_ms <= max_ms, string.format('%s budget exceeded: %.2fms > %dms', label, elapsed_ms, max_ms))
end

local function wait_for(predicate, timeout_ms, step_ms)
  timeout_ms = timeout_ms or 8000
  step_ms = step_ms or 20
  return vim.wait(timeout_ms, predicate, step_ms) == true
end

local function payload_text(payload)
  if type(payload) ~= 'table' then
    return tostring(payload or '')
  end
  if type(payload.lines) == 'table' then
    return table.concat(payload.lines, '\n')
  end
  if type(payload[1]) == 'string' then
    return table.concat(payload, '\n')
  end
  return vim.inspect(payload)
end

local function run_exec_cell_and_wait(buf, cell_lines, opts)
  opts = opts or {}
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, cell_lines)
  local state = index.rebuild(buf)
  local cell = state.list[1]
  local out = nil
  local got_output = false
  local start = now_ms()
  local ok_run, err, level = exec.run_cell(buf, 1, {
    cell_id = cell and cell.id or nil,
    on_output = function(payload)
      out = payload_text(payload)
      got_output = true
    end,
  })
  ok(ok_run, err or level)
  local settled = wait_for(function()
    local st = exec.get_session_state(buf)
    return got_output and st and st.active_request == false and st.queue_len == 0
  end, opts.timeout_ms or 12000, 20)
  ok(settled, opts.label or 'execution did not settle in time')
  return now_ms() - start, out or ''
end

with_buf({ "" }, function(buf)
  -- Budget values are intentionally conservative to avoid CI flakiness while still
  -- catching major regressions.
  local budget = {
    import_jupytext = 4500,
    rebuild_index = 2500,
    render = 3500,
    export_ipynb = 4500,
    import_ipynb = 4500,
    batch_compute = 8000,
    large_output = 10000,
    local_fetch = 8000,
  }

  local large_percent = fixture_root .. '/large_percent.py'
  local large_ipynb = fixture_root .. '/large_notebook.ipynb'
  local exported_tmp = vim.fn.tempname() .. '.ipynb'

  local ok_import_jt, import_jt_ms, imported, err = timed(function()
    return ipynb.import_jupytext(large_percent, buf)
  end)
  ok(ok_import_jt, 'import_jupytext timing call failed')
  ok(imported, err)
  assert_budget('import_jupytext', import_jt_ms, budget.import_jupytext)

  local ok_rebuild, rebuild_ms = timed(function()
    index.rebuild(buf)
  end)
  ok(ok_rebuild, 'index.rebuild timing call failed')
  assert_budget('index.rebuild', rebuild_ms, budget.rebuild_index)

  local ok_render, render_ms = timed(function()
    render.render(buf)
  end)
  ok(ok_render, 'render.render timing call failed')
  assert_budget('render.render', render_ms, budget.render)

  local ok_export, export_ms, exported_ok, export_err = timed(function()
    return ipynb.export_ipynb(exported_tmp, buf)
  end)
  ok(ok_export, 'export_ipynb timing call failed')
  ok(exported_ok, export_err)
  assert_budget('export_ipynb', export_ms, budget.export_ipynb)

  local ok_import_ipynb, import_ipynb_ms, imported_ok, import_err = timed(function()
    return ipynb.import_ipynb(large_ipynb, buf)
  end)
  ok(ok_import_ipynb, 'import_ipynb timing call failed')
  ok(imported_ok, import_err)
  assert_budget('import_ipynb', import_ipynb_ms, budget.import_ipynb)

  local state = index.rebuild(buf)
  ok(#state.list >= 100, 'large ipynb produced substantial cell count')

  local batch_ms, batch_out = run_exec_cell_and_wait(buf, {
    '# %% [code]',
    'total = 0',
    'for batch in range(50):',
    '    start = batch * 100',
    '    subtotal = 0',
    '    for i in range(start, start + 100):',
    '        subtotal += ((i * i) + (3 * i)) % 97',
    '    total += subtotal',
    "print('BATCH_DONE', total)",
  }, { label = 'batch compute did not finish in time' })
  assert_budget('batch_compute', batch_ms, budget.batch_compute)
  ok(batch_out:find('BATCH_DONE', 1, true) ~= nil, 'batch compute output marker present')

  local output_ms, output_out = run_exec_cell_and_wait(buf, {
    '# %% [code]',
    'for i in range(2500):',
    "    print(f'ROW:{i}')",
  }, { label = 'large output stream did not finish in time', timeout_ms = 15000 })
  assert_budget('large_output', output_ms, budget.large_output)
  ok(output_out:find('ROW:0', 1, true) ~= nil, 'large output contains first row')
  ok(output_out:find('ROW:2499', 1, true) ~= nil, 'large output contains final row')

  local payload_path = vim.fn.tempname() .. '.json'
  local rows = {}
  for i = 1, 5000 do
    rows[#rows + 1] = i
  end
  local ok_write_payload = pcall(vim.fn.writefile, { vim.fn.json_encode({ rows = rows }) }, payload_path)
  ok(ok_write_payload, 'wrote local fetch payload')
  local file_url = 'file://' .. payload_path
  local fetch_ms, fetch_out = run_exec_cell_and_wait(buf, {
    '# %% [code]',
    'import json',
    'import urllib.request',
    string.format("with urllib.request.urlopen('%s') as r:", file_url),
    "    data = json.loads(r.read().decode('utf-8'))",
    "print('FETCH_ROWS', len(data['rows']))",
  }, { label = 'local fetch workload did not finish in time' })
  assert_budget('local_fetch', fetch_ms, budget.local_fetch)
  ok(fetch_out:find('FETCH_ROWS 5000', 1, true) ~= nil, 'local fetch loaded expected row count')

  if vim.g.neo_notebooks_test_include_network then
    local net_ms, net_out = run_exec_cell_and_wait(buf, {
      '# %% [code]',
      'import json',
      'import urllib.request',
      "with urllib.request.urlopen('https://httpbin.org/json', timeout=5) as r:",
      "    data = json.loads(r.read().decode('utf-8'))",
      "print('NET_OK', bool(data.get('slideshow')))",
    }, { label = 'network fetch workload did not finish in time', timeout_ms = 15000 })
    print(string.format('performance network metric (ms): fetch_httpbin=%.1f', net_ms))
    ok(net_out:find('NET_OK True', 1, true) ~= nil, 'network fetch returned expected shape')
  end

  exec.stop_session(buf)

  print(string.format(
    'performance metrics (ms): import_jupytext=%.1f rebuild=%.1f render=%.1f export=%.1f import_ipynb=%.1f batch=%.1f stream=%.1f fetch_local=%.1f',
    import_jt_ms, rebuild_ms, render_ms, export_ms, import_ipynb_ms, batch_ms, output_ms, fetch_ms
  ))
end)

print('performance tests passed')
