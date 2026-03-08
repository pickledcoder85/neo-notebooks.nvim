local t = require('tests._helpers')
t.setup()

local ok = t.ok
local eq = t.eq
local with_buf = t.with_buf

local index = require('neo_notebooks.index')
local cells = require('neo_notebooks.cells')
local output = require('neo_notebooks.output')
local render = require('neo_notebooks.render')
local index_mod = require('neo_notebooks.index')
local ipynb = require('neo_notebooks.ipynb')
local nb = require('neo_notebooks')
local exec = require('neo_notebooks.exec')
local session = require('neo_notebooks.session')
local badge = require('neo_notebooks.kernel_status_badge')
local fixture_root = vim.fn.getcwd() .. '/tests/fixtures/jupytext'

-- Test: default strict containment mode is soft
eq(nb.config.strict_containment, "soft", "strict containment default")

-- Test: index build
with_buf({
  "# %% [code]",
  "print(1)",
  "",
  "# %% [markdown]",
  "# Title",
}, function(buf)
  local state = index.rebuild(buf)
  eq(#state.list, 2, "cell count")
  ok(state.list[1].id, "id set")
  ok(state.by_id[state.list[1].id], "by_id has entry")
  eq(state.list[1].type, "code", "first type")
  eq(state.list[2].type, "markdown", "second type")
end)

-- Test: marker delete/reinsert preserves cell id
with_buf({
  "# %% [code]",
  "print(1)",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local id2 = index.get(buf).list[2].id
  -- delete marker line for second cell
  vim.api.nvim_buf_set_lines(buf, 2, 3, false, {})
  index.on_lines(buf, 2, 3, 2)
  -- reinsert marker line
  vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "# %% [code]" })
  index.on_lines(buf, 2, 2, 3)
  local state = index.get(buf)
  eq(state.list[2].id, id2, "id stable after marker delete/reinsert")
end)

-- Test: stable id across rebuild after body edit
with_buf({
  "# %% [code]",
  "print(1)",
  "",
}, function(buf)
  local state = index.rebuild(buf)
  local id = state.list[1].id
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "print(2)" })
  state = index.rebuild(buf)
  eq(state.list[1].id, id, "id stable after edit")
end)

-- Test: line insert without marker touch updates ranges without rebuild
with_buf({
  "# %% [code]",
  "print(1)",
  "# %% [code]",
  "print(2)",
}, function(buf)
  local state = index.rebuild(buf)
  local first = state.list[1]
  local second = state.list[2]
  -- insert a line inside first cell body (before second marker)
  vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "print(1.5)" })
  index.on_lines(buf, 2, 2, 3)
  local updated = index.get(buf)
  eq(updated.list[1].id, first.id, "id stable after insert")
  eq(updated.list[2].id, second.id, "second id stable after insert")
  eq(updated.list[2].start, second.start + 1, "second start shifted after insert")
end)

-- Test: marker type edit updates cell type without full rebuild
with_buf({
  "# %% [code]",
  "print(1)",
  "# %% [code]",
  "print(2)",
}, function(buf)
  local state = index.rebuild(buf)
  local marks = vim.api.nvim_buf_get_extmarks(buf, index_mod.ns, { 0, 0 }, { -1, -1 }, {})
  ok(#marks > 0, "marker extmark exists")
  local first_id = marks[1][1]
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "# %% [markdown]" })
  vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "" })
  index.on_lines(buf, 0, 1, 1)
  local updated_state = vim.b[buf].neo_notebooks_index
  eq(updated_state.list[1].id, first_id, "id stable after marker type change")
  eq(updated_state.list[1].type, "markdown", "marker type updated in place")
  local marks_after = vim.api.nvim_buf_get_extmarks(buf, index_mod.ns, { 0, 0 }, { -1, -1 }, {})
  local seen = {}
  for _, mark in ipairs(marks_after) do
    seen[mark[1]] = true
  end
  ok(seen[first_id], "extmark id stable after marker type change")
end)

-- Test: dirty set accumulates multiple touched cells
with_buf({
  "# %% [code]",
  "line1",
  "",
  "# %% [code]",
  "line2",
  "",
  "# %% [code]",
  "line3",
}, function(buf)
  local state = index.rebuild(buf)
  local ids = {
    state.list[1].id,
    state.list[2].id,
    state.list[3].id,
  }
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "a" })
  index.on_lines(buf, 1, 2, 2)
  vim.api.nvim_buf_set_lines(buf, 4, 5, false, { "b" })
  index.on_lines(buf, 4, 5, 5)
  local dirty = index.consume_dirty_cells(buf)
  ok(dirty and #dirty >= 2, "dirty set contains all touched cells")
  local seen = {}
  for _, id in ipairs(dirty) do
    seen[id] = true
  end
  ok(seen[ids[1]] and seen[ids[2]], "touched cells marked dirty")
end)

-- Test: get_cell_at_line uses index
with_buf({
  "# %% [code]",
  "print(1)",
  "# %% [code]",
  "print(2)",
}, function(buf)
  index.rebuild(buf)
  local cell = cells.get_cell_at_line(buf, 2)
  eq(cell.start, 2, "cell lookup by line")
end)

-- Test: get_cells ignores render tail padding lines
with_buf({
  "# %% [code]",
  "print(1)",
  "",
}, function(buf)
  vim.api.nvim_buf_set_lines(buf, 3, 3, false, { "", "", "" })
  vim.api.nvim_buf_set_var(buf, "neo_notebooks_tail_pad", 3)
  local list = cells.get_cells(buf)
  eq(list[1].finish, 2, "tail pad excluded from cell finish")
end)

-- Test: ipynb import/export preserves metadata + outputs
with_buf({ "" }, function(buf)
  local tmp = vim.fn.tempname() .. ".ipynb"
  local doc = {
    nbformat = 4,
    nbformat_minor = 5,
    metadata = { kernelspec = { name = "python3" }, custom = { foo = "bar" } },
    cells = {
      {
        cell_type = "markdown",
        metadata = { tags = { "intro" } },
        source = { "# Title\n" },
      },
      {
        cell_type = "code",
        metadata = { tags = { "code" } },
        execution_count = 3,
        source = { "print('hi')\n" },
        outputs = {
          { output_type = "stream", name = "stdout", text = "hi\n" },
          { output_type = "error", ename = "ValueError", evalue = "bad", traceback = { "Traceback line\n" } },
          { output_type = "display_data", data = { ["text/plain"] = "ok" }, metadata = {} },
        },
      },
    },
  }
  local ok_write = pcall(vim.fn.writefile, { vim.fn.json_encode(doc) }, tmp)
  ok(ok_write, "wrote temp ipynb")

  local ok_import, err = ipynb.import_ipynb(tmp, buf)
  ok(ok_import, err)

  local state = vim.api.nvim_buf_get_var(buf, "neo_notebooks_ipynb_state")
  eq(state.metadata.custom.foo, "bar", "metadata preserved")
  eq(#state.order, 2, "cell order stored")
  local code_id = state.order[2]
  eq(state.cells[code_id].execution_count, 3, "execution_count preserved")
  eq(#state.cells[code_id].outputs, 3, "outputs preserved")

  local tmp_out = vim.fn.tempname() .. ".ipynb"
  local ok_export, err_export = ipynb.export_ipynb(tmp_out, buf)
  ok(ok_export, err_export)
  local exported = vim.fn.json_decode(table.concat(vim.fn.readfile(tmp_out), "\n"))
  eq(exported.metadata.custom.foo, "bar", "export metadata preserved")
  eq(#exported.cells, 2, "export cell count")
  eq(exported.cells[2].execution_count, 3, "export execution_count")
  eq(#exported.cells[2].outputs, 3, "export outputs preserved")
end)

-- Test: ipynb import renders html/json MIME and suppresses plain fallback repr
with_buf({ "" }, function(buf)
  local tmp = vim.fn.tempname() .. ".ipynb"
  local doc = {
    nbformat = 4,
    nbformat_minor = 5,
    metadata = {},
    cells = {
      {
        cell_type = "code",
        metadata = {},
        execution_count = 2,
        source = { "pass\n" },
        outputs = {
          {
            output_type = "execute_result",
            execution_count = 1,
            metadata = {},
            data = {
              ["text/html"] = "<b>HTML OK</b><br><i>interop test</i>",
              ["text/plain"] = "<IPython.core.display.HTML object>",
            },
          },
          {
            output_type = "execute_result",
            execution_count = 2,
            metadata = { ["application/json"] = { expanded = false } },
            data = {
              ["application/json"] = { k = "v", n = 42 },
              ["text/plain"] = "<IPython.core.display.JSON object>",
            },
          },
        },
      },
    },
  }
  local ok_write = pcall(vim.fn.writefile, { vim.fn.json_encode(doc) }, tmp)
  ok(ok_write, "wrote temp ipynb")

  local ok_import, err = ipynb.import_ipynb(tmp, buf)
  ok(ok_import, err)

  local state = vim.api.nvim_buf_get_var(buf, "neo_notebooks_ipynb_state")
  local code_id = state.order[1]
  local lines = output.get_lines(buf, code_id) or {}
  local joined = table.concat(lines, "\n")
  ok(joined:find("HTML OK", 1, true) ~= nil, "html content rendered")
  ok(joined:find("interop test", 1, true) ~= nil, "html line break rendered")
  ok(joined:find("\"k\"", 1, true) ~= nil, "json key rendered")
  ok(joined:find("\"v\"", 1, true) ~= nil, "json value rendered")
  ok(joined:find("\"n\"", 1, true) ~= nil, "json numeric key rendered")
  ok(joined:find("42", 1, true) ~= nil, "json number rendered")
  ok(joined:find("<IPython.core.display.HTML object>", 1, true) == nil, "html plain fallback suppressed")
  ok(joined:find("<IPython.core.display.JSON object>", 1, true) == nil, "json plain fallback suppressed")
end)

-- Test: jupytext py:percent import parses markdown and preserves jupytext metadata on ipynb export
with_buf({ "" }, function(buf)
  local tmp = vim.fn.tempname() .. ".py"
  local lines = {
    "# ---",
    "# jupyter:",
    "#   jupytext:",
    "#     formats: ipynb,py:percent",
    "#     text_representation:",
    "#       extension: .py",
    "#       format_name: percent",
    "#       format_version: '1.3'",
    "# ---",
    "# %% [markdown]",
    "# # Title",
    "# plain line",
    "#",
    "# %% [code]",
    "print('hi')",
  }
  local ok_write = pcall(vim.fn.writefile, lines, tmp)
  ok(ok_write, "wrote temp jupytext file")

  local ok_import, err = ipynb.import_jupytext(tmp, buf)
  ok(ok_import, err)

  local out = vim.api.nvim_buf_get_lines(buf, 0, 8, false)
  eq(out[1], "# %% [markdown]", "markdown marker imported")
  eq(out[2], "# Title", "markdown heading converted from commented percent line")
  eq(out[3], "plain line", "markdown plain line converted from commented percent line")

  local state = vim.api.nvim_buf_get_var(buf, "neo_notebooks_ipynb_state")
  ok(state.metadata and state.metadata.jupytext, "jupytext metadata captured")
  eq(state.metadata.jupytext.formats, "ipynb,py:percent", "jupytext formats preserved")
  eq(state.metadata.jupytext.text_representation.format_name, "percent", "jupytext format name preserved")

  local tmp_out = vim.fn.tempname() .. ".ipynb"
  local ok_export, err_export = ipynb.export_ipynb(tmp_out, buf)
  ok(ok_export, err_export)
  local exported = vim.fn.json_decode(table.concat(vim.fn.readfile(tmp_out), "\n"))
  ok(exported.metadata and exported.metadata.language_info, "export metadata is object-shaped")
  eq(exported.metadata.language_info.name, "python", "export language_info preserved/defaulted")
  ok(exported.metadata and exported.metadata.jupytext, "export includes jupytext metadata")
  eq(exported.metadata.jupytext.formats, "ipynb,py:percent", "export jupytext formats")
  eq(exported.metadata.jupytext.text_representation.format_name, "percent", "export jupytext format name")
end)

-- Test: jupytext import without header still seeds default jupytext metadata
with_buf({ "" }, function(buf)
  local tmp = vim.fn.tempname() .. ".py"
  local lines = {
    "# %% [code]",
    "x = 1",
  }
  local ok_write = pcall(vim.fn.writefile, lines, tmp)
  ok(ok_write, "wrote temp jupytext file")

  local ok_import, err = ipynb.import_jupytext(tmp, buf)
  ok(ok_import, err)

  local state = vim.api.nvim_buf_get_var(buf, "neo_notebooks_ipynb_state")
  ok(state.metadata and state.metadata.jupytext, "default jupytext metadata seeded")
  eq(state.metadata.jupytext.text_representation.format_name, "percent", "default format_name is percent")
end)

-- Test: jupytext fixture from upstream README ("Text Notebooks") imports/exports expected shape
-- Source: https://github.com/mwouts/jupytext
with_buf({ "" }, function(buf)
  local path = fixture_root .. "/readme_basic_percent.py"
  local ok_import, err = ipynb.import_jupytext(path, buf)
  ok(ok_import, err)

  local out = vim.api.nvim_buf_get_lines(buf, 0, 9, false)
  eq(out[1], "# %% [markdown]", "fixture markdown marker")
  eq(out[2], "This is a markdown cell", "fixture markdown content")
  eq(out[4], "# %% [code]", "fixture code marker")
  eq(out[5], "def f(x):", "fixture code content")

  local tmp_out = vim.fn.tempname() .. ".ipynb"
  local ok_export, err_export = ipynb.export_ipynb(tmp_out, buf)
  ok(ok_export, err_export)
  local exported = vim.fn.json_decode(table.concat(vim.fn.readfile(tmp_out), "\n"))
  eq(#exported.cells, 3, "fixture export cell count")
  eq(exported.cells[1].cell_type, "markdown", "fixture first cell markdown")
end)

-- Test: jupytext fixture from upstream docs preserves header metadata and marker variants
-- Source: https://jupytext.readthedocs.io/en/latest/formats-scripts.html
with_buf({ "" }, function(buf)
  local path = fixture_root .. "/docs_percent_with_header.py"
  local ok_import, err = ipynb.import_jupytext(path, buf)
  ok(ok_import, err)

  local state = vim.api.nvim_buf_get_var(buf, "neo_notebooks_ipynb_state")
  ok(state.metadata and state.metadata.jupytext, "docs fixture captured jupytext metadata")
  eq(state.metadata.jupytext.formats, "ipynb,py:percent", "docs fixture formats parsed")
  eq(state.metadata.jupytext.text_representation.format_name, "percent", "docs fixture format_name parsed")

  local idx = index.rebuild(buf)
  eq(#idx.list, 4, "docs fixture parsed into four cells")
  eq(idx.list[1].type, "markdown", "docs fixture first markdown")
  eq(idx.list[2].type, "markdown", "docs fixture title marker markdown")
  eq(idx.list[3].type, "code", "docs fixture third code")
end)

-- Test: kernel queue pause/resume toggles paused session state
with_buf({
  "# %% [code]",
  "x = 1",
}, function(buf)
  local ok_pause = exec.pause_queue(buf)
  ok(ok_pause, "pause queue succeeds")
  local paused = exec.get_session_state(buf)
  ok(paused.paused == true, "session state paused=true")

  local paused_flag = exec.toggle_pause_queue(buf)
  eq(paused_flag, false, "toggle from paused returns false (resumed)")
  local resumed = exec.get_session_state(buf)
  ok(resumed.paused == false, "session state paused=false after resume")
end)

-- Test: restart clears paused flag
with_buf({
  "# %% [code]",
  "x = 1",
}, function(buf)
  exec.pause_queue(buf)
  local before = exec.get_session_state(buf)
  ok(before.paused == true, "paused before restart")
  session.restart(buf)
  local after = exec.get_session_state(buf)
  ok(after.paused == false, "restart clears paused flag")
  eq(after.state, "idle", "restart returns state to idle")
end)

-- Test: stop clears paused flag and sets stopped state
with_buf({
  "# %% [code]",
  "x = 1",
}, function(buf)
  exec.pause_queue(buf)
  local before = exec.get_session_state(buf)
  ok(before.paused == true, "paused before stop")
  exec.stop_session(buf)
  local after = exec.get_session_state(buf)
  ok(after.paused == false, "stop clears paused flag")
  eq(after.state, "stopped", "stop sets state stopped")
  eq(nb.kernel_status(buf), "stopped", "kernel_status reports stopped after stop")
end)

-- Test: failed session start sets error state
with_buf({
  "# %% [code]",
  "x = 1",
}, function(buf)
  local prev = nb.config.python_cmd
  nb.config.python_cmd = "/path/that/does/not/exist/python"
  local ok_run = exec.run_cell(buf, 1)
  ok(not ok_run, "run fails when python command is invalid")
  local state = exec.get_session_state(buf)
  eq(state.state, "error", "session state becomes error on start failure")
  nb.config.python_cmd = prev
end)

-- Test: virtual kernel badge renders when enabled and clears when disabled
with_buf({
  "# %% [code]",
  "x = 1",
}, function(buf)
  vim.b[buf].neo_notebooks_enabled = true
  local prev = nb.config.kernel_status_virtual
  nb.config.kernel_status_virtual = true
  badge.refresh(buf)
  local marks = vim.api.nvim_buf_get_extmarks(buf, badge.ns, { 0, 0 }, { -1, -1 }, { details = true })
  ok(#marks > 0, "virtual kernel badge extmark created")

  nb.config.kernel_status_virtual = false
  badge.refresh(buf)
  local after = vim.api.nvim_buf_get_extmarks(buf, badge.ns, { 0, 0 }, { -1, -1 }, { details = true })
  eq(#after, 0, "virtual kernel badge cleared when disabled")
  nb.config.kernel_status_virtual = prev
end)

print('core_contract tests passed')
