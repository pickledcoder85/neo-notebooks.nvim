local t = require('tests._helpers')
t.setup()

local ok = t.ok
local with_buf = t.with_buf

local index = require('neo_notebooks.index')
local render = require('neo_notebooks.render')
local ipynb = require('neo_notebooks.ipynb')

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

with_buf({ "" }, function(buf)
  -- Budget values are intentionally conservative to avoid CI flakiness while still
  -- catching major regressions.
  local budget = {
    import_jupytext = 4500,
    rebuild_index = 2500,
    render = 3500,
    export_ipynb = 4500,
    import_ipynb = 4500,
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

  print(string.format(
    'performance metrics (ms): import_jupytext=%.1f rebuild=%.1f render=%.1f export=%.1f import_ipynb=%.1f',
    import_jt_ms, rebuild_ms, render_ms, export_ms, import_ipynb_ms
  ))
end)

print('performance tests passed')
