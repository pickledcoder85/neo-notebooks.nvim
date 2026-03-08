local M = {}

function M.register(ctx)
  local nb = ctx.nb
  local cells = ctx.cells
  local render = ctx.render
  local exec = ctx.exec
  local markdown = ctx.markdown
  local output = ctx.output
  local overlay = ctx.overlay
  local navigation = ctx.navigation
  local actions = ctx.actions
  local ipynb = ctx.ipynb
  local run_all = ctx.run_all
  local session = ctx.session
  local stats = ctx.stats
  local run_subset = ctx.run_subset
  local help = ctx.help
  local editor = ctx.editor
  local index = ctx.index
  local scheduler = ctx.scheduler
  local snake = ctx.snake

  local set_python_filetype = ctx.set_python_filetype
  local should_enable = ctx.should_enable
  local ensure_top_padding = ctx.ensure_top_padding
  local render_if_enabled = ctx.render_if_enabled
  local reset_undo_baseline = ctx.reset_undo_baseline
  local set_default_keymaps = ctx.set_default_keymaps
  local set_snake_keymaps = ctx.set_snake_keymaps
  local clear_snake_keymaps = ctx.clear_snake_keymaps

  local function logical_cell_insert_base(bufnr, cell)
    local body = vim.api.nvim_buf_get_lines(bufnr, cell.start + 1, cell.finish + 1, false)
    local last_nonempty = nil
    for i = #body, 1, -1 do
      if body[i] ~= "" then
        last_nonempty = cell.start + i
        break
      end
    end
    if not last_nonempty then
      return cell.start + 1
    end
    return last_nonempty + 1
  end

  local function run_cell_with_output(line, cell)
    local bufnr = vim.api.nvim_get_current_buf()
    local index_mod = require("neo_notebooks.index")
    local entry = index_mod.find_cell(bufnr, line)
    if entry and not cell.id then
      cell.id = entry.id
      cell.start = entry.start
      cell.finish = entry.finish
    end
    if nb.config.output == "inline" then
      local ok, err, level = exec.run_cell(bufnr, line, {
        on_output = function(payload, cell_id, duration_ms)
          if vim.b[bufnr] and vim.b[bufnr].neo_notebooks_is_ipynb and cell_id and payload and payload.items then
            require("neo_notebooks.ipynb").update_cell_output(bufnr, cell_id, payload)
          end
          output.show_payload(bufnr, {
            id = cell_id or cell.id,
            start = cell.start,
            finish = cell.finish,
            type = cell.type,
          }, payload, { duration_ms = duration_ms })
        end,
        cell_id = cell.id,
      })
      if not ok and err then
        vim.notify(err, level or vim.log.levels.WARN)
      end
    else
      local ok, err, level = exec.run_cell(bufnr, line)
      if not ok and err then
        vim.notify(err, level or vim.log.levels.WARN)
      end
    end
  end

  vim.api.nvim_create_user_command("NeoNotebookRender", function()
    render.render(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellNew", function(opts)
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local insert_line = cells.insert_cell_below(0, line, opts.args)
    vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
    actions.clamp_cursor_to_cell_left(0, { force = true })
    render_if_enabled(0)
    vim.cmd("startinsert")
  end, { nargs = "?", complete = function() return { "code", "markdown" } end })

  vim.api.nvim_create_user_command("NeoNotebookCellToggleType", function()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    cells.toggle_cell_type(0, line)
    render_if_enabled(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellRun", function()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local cell = cells.get_cell_at_line(0, line)
    actions.consume_pending_virtual_indent(0)
    run_cell_with_output(line, cell)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellRunAndNext", function()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local cell = cells.get_cell_at_line(0, line)
    local list = cells.get_cells(0)
    local next_cell = nil
    for i, item in ipairs(list) do
      if item.start == cell.start then
        next_cell = list[i + 1]
        break
      end
    end

    if cell.type == "markdown" then
      if next_cell then
        local max_line = vim.api.nvim_buf_line_count(0)
        local target = math.min(next_cell.start + 2, max_line)
        vim.api.nvim_win_set_cursor(0, { target, 0 })
        actions.clamp_cursor_to_cell_left(0, { force = true })
      else
        local insert_base = logical_cell_insert_base(0, cell)
        local insert_line = cells.insert_cell_below(0, insert_base, "code")
        local max_line = vim.api.nvim_buf_line_count(0)
        local target = math.min(insert_line + 2, max_line)
        vim.api.nvim_win_set_cursor(0, { target, 0 })
        render_if_enabled(0)
        actions.clamp_cursor_to_cell_left(0, { force = true })
        vim.cmd("startinsert")
      end
      return
    end

    if not next_cell and not actions.cell_has_nonempty_body(0, line) then
      vim.notify("NeoNotebook: current code cell is empty; not adding another cell", vim.log.levels.INFO)
      local max_line = vim.api.nvim_buf_line_count(0)
      local target = math.min(cell.start + 2, max_line)
      vim.api.nvim_win_set_cursor(0, { target, 0 })
      actions.clamp_cursor_to_cell_left(0, { force = true })
      vim.cmd("startinsert")
      return
    end

    actions.consume_pending_virtual_indent(0)
    run_cell_with_output(line, cell)

    if next_cell then
      local max_line = vim.api.nvim_buf_line_count(0)
      local target = math.min(next_cell.start + 2, max_line)
      vim.api.nvim_win_set_cursor(0, { target, 0 })
      actions.clamp_cursor_to_cell_left(0, { force = true })
    else
      local insert_base = logical_cell_insert_base(0, cell)
      local insert_line = cells.insert_cell_below(0, insert_base, "code")
      local max_line = vim.api.nvim_buf_line_count(0)
      local target = math.min(insert_line + 2, max_line)
      vim.api.nvim_win_set_cursor(0, { target, 0 })
      render_if_enabled(0)
      actions.clamp_cursor_to_cell_left(0)
      vim.cmd("startinsert")
    end
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookMarkdownPreview", function()
    local ok, err, level = markdown.preview_cell(0)
    if not ok and err then
      vim.notify(err, level or vim.log.levels.WARN)
    end
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellOverlayToggle", function()
    overlay.toggle(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookAutoRenderToggle", function()
    local enabled = actions.toggle_auto_render()
    vim.notify(string.format("NeoNotebook: auto_render = %s", tostring(enabled)), vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellIndexToggle", function()
    local show = actions.toggle_cell_index()
    vim.notify(string.format("NeoNotebook: show_cell_index = %s", tostring(show)), vim.log.levels.INFO)
    render_if_enabled(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellNext", function()
    navigation.next_cell(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellPrev", function()
    navigation.prev_cell(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellList", function()
    navigation.cell_list(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellDuplicate", function()
    actions.duplicate_cell(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellSplit", function()
    local ok, err = actions.split_cell(0)
    if not ok and err then
      vim.notify(err, vim.log.levels.WARN)
    end
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellFold", function()
    actions.fold_cell(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellUnfold", function()
    actions.unfold_cell(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellFoldToggle", function()
    actions.toggle_fold_cell(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookOutputClear", function()
    actions.clear_output(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookOutputClearAll", function()
    actions.clear_all_output(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookOutputCollapseToggle", function()
    local collapsed, err = actions.toggle_output_collapse(0)
    if collapsed == nil then
      vim.notify(err or "NeoNotebook: no output to collapse", vim.log.levels.WARN)
      return
    end
    local label = collapsed and "collapsed" or "expanded"
    vim.notify("NeoNotebook: output " .. label, vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookOutputPrint", function()
    local text, err = actions.print_output(0)
    if not text then
      vim.notify(err or "NeoNotebook: no output to print", vim.log.levels.WARN)
      return
    end
    vim.notify(text, vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookImageClear", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local cell = cells.get_cell_at_line(bufnr, line)
    if not cell or not cell.id then
      return
    end
    output.clear_images(bufnr, cell.id)
    scheduler.request_render(bufnr, { immediate = true, cell_ids = { cell.id } })
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookImagePaneTest", function(opts)
    local path = opts.args
    if path == "" then
      path = vim.fn.getcwd() .. "/mainecoon"
    end
    path = vim.fn.fnamemodify(path, ":p")
    local pane = require("neo_notebooks.image_pane")
    pane.open()
    local ok = pane.render_file(path, "Image Test")
    if not ok then
      vim.notify("NeoNotebook: image pane test failed", vim.log.levels.WARN)
    end
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("NeoNotebookImagePaneReset", function()
    require("neo_notebooks.image_pane").reset()
    vim.notify("NeoNotebook: image pane reset", vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellDelete", function()
    actions.delete_cell(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellYank", function()
    local ok = actions.yank_cell(0)
    if ok then
      vim.notify("NeoNotebook: cell yanked", vim.log.levels.INFO)
    end
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellMoveUp", function()
    actions.move_cell_up(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellMoveDown", function()
    actions.move_cell_down(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookRunAll", function()
    actions.consume_pending_virtual_indent(0)
    run_all.run_all(vim.api.nvim_get_current_buf())
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookRestart", function()
    local ok = session.restart(0)
    if ok then
      vim.notify("NeoNotebook: Python session restarted", vim.log.levels.INFO)
    end
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookOutputToggle", function()
    local mode = actions.toggle_output_mode()
    vim.notify("NeoNotebook: output mode = " .. tostring(mode), vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellSelect", function()
    actions.select_cell(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookStats", function()
    local result = stats.show(0)
    if result and result.message then
      vim.notify(result.message, vim.log.levels.INFO)
    end
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookRunAbove", function()
    actions.consume_pending_virtual_indent(0)
    run_subset.run_above(vim.api.nvim_get_current_buf())
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookRunBelow", function()
    actions.consume_pending_virtual_indent(0)
    run_subset.run_below(vim.api.nvim_get_current_buf())
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookHelp", function()
    help.show()
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellEdit", function()
    editor.edit_cell(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellSave", function()
    local ok, err, level = editor.save_current()
    if not ok then
      vim.notify(err or "Save failed", level or vim.log.levels.ERROR)
      return
    end
    vim.notify("NeoNotebook: cell saved", vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookCellRunFromEditor", function()
    local ok, err, level = editor.run_from_editor()
    if not ok and err then
      vim.notify(err, level or vim.log.levels.ERROR)
    end
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookImportIpynb", function(opts)
    local path = opts.args
    if path == "" then
      vim.notify("Provide a .ipynb path", vim.log.levels.WARN)
      return
    end
    local ok, err = ipynb.import_ipynb(path, 0)
    if not ok then
      vim.notify(err or "Import failed", vim.log.levels.ERROR)
      return
    end
    ensure_top_padding(0)
    reset_undo_baseline(0)
    render_if_enabled(0)
  end, { nargs = 1, complete = "file" })

  vim.api.nvim_create_user_command("NeoNotebookOpenIpynb", function(opts)
    local path = opts.args
    if path == "" then
      vim.notify("Provide a .ipynb path", vim.log.levels.WARN)
      return
    end
    local ok, err = ipynb.open_ipynb(path)
    if not ok then
      vim.notify(err or "Open failed", vim.log.levels.ERROR)
      return
    end
    reset_undo_baseline(0)
  end, { nargs = 1, complete = "file" })

  vim.api.nvim_create_user_command("NeoNotebookImportJupytext", function(opts)
    local path = opts.args
    if path == "" then
      vim.notify("Provide a Jupytext .py path", vim.log.levels.WARN)
      return
    end
    local bufnr = vim.api.nvim_get_current_buf()
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
    local modifiable = vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
    if buftype == "nofile" or not modifiable then
      vim.cmd("enew")
      bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_name(bufnr, path .. ".nn")
    end
    vim.b[bufnr].neo_notebooks_enabled = true
    set_python_filetype(bufnr)
    local ok, err = ipynb.import_jupytext(path, bufnr)
    if not ok then
      vim.notify(err or "Jupytext import failed", vim.log.levels.ERROR)
      return
    end
    ensure_top_padding(bufnr)
    reset_undo_baseline(bufnr)
    index.mark_dirty(bufnr)
    index.attach(bufnr)
    set_default_keymaps(bufnr)
    render_if_enabled(bufnr)
  end, { nargs = 1, complete = "file" })

  vim.api.nvim_create_user_command("NeoNotebookOpenJupytext", function(opts)
    local path = opts.args
    if path == "" then
      vim.notify("Provide a Jupytext .py path", vim.log.levels.WARN)
      return
    end
    local ok, err, bufnr = ipynb.open_jupytext(path)
    if not ok then
      vim.notify(err or "Jupytext open failed", vim.log.levels.ERROR)
      return
    end
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    vim.b[bufnr].neo_notebooks_enabled = true
    set_python_filetype(bufnr)
    ensure_top_padding(bufnr)
    reset_undo_baseline(bufnr)
    index.mark_dirty(bufnr)
    index.attach(bufnr)
    set_default_keymaps(bufnr)
    render_if_enabled(bufnr)
  end, { nargs = 1, complete = "file" })

  vim.api.nvim_create_user_command("NeoNotebookSnakeCell", function()
    local bufnr = vim.api.nvim_get_current_buf()
    if not should_enable(bufnr) then
      vim.notify("NeoNotebook: snake mode requires a notebook buffer", vim.log.levels.WARN)
      return
    end
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local insert_line = cells.insert_cell_below(bufnr, line, "code")
    local state = index.rebuild(bufnr)
    local entry = nil
    for _, cell in ipairs(state.list or {}) do
      if cell.start == insert_line and cell.type == "code" then
        entry = cell
        break
      end
    end
    if not entry then
      entry = cells.get_cell_at_line(bufnr, insert_line)
    end
    if not entry or not entry.id then
      vim.notify("NeoNotebook: failed to create snake cell", vim.log.levels.ERROR)
      return
    end
    local ok, err = snake.start(bufnr, entry.id, {
      on_exit = function()
        clear_snake_keymaps(bufnr)
        set_default_keymaps(bufnr)
        render_if_enabled(bufnr)
      end,
    })
    if not ok then
      vim.notify("NeoNotebook: " .. (err or "failed to start snake mode"), vim.log.levels.ERROR)
      return
    end
    set_snake_keymaps(bufnr)
    vim.api.nvim_win_set_cursor(0, { entry.start + 2, 0 })
    render_if_enabled(bufnr)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookExportIpynb", function(opts)
    local path = opts.args
    if path == "" then
      vim.notify("Provide a .ipynb path", vim.log.levels.WARN)
      return
    end
    actions.consume_pending_virtual_indent(0)
    local ok, err = ipynb.export_ipynb(path, 0)
    if not ok then
      vim.notify(err or "Export failed", vim.log.levels.ERROR)
    end
  end, { nargs = 1, complete = "file" })

  vim.api.nvim_create_user_command("NeoNotebookEnable", function()
    render_if_enabled(0)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookOutputHasAnsi", function()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local cell = cells.get_cell_at_line(0, line)
    if not cell or not cell.id then
      vim.notify("NeoNotebook: no cell id found", vim.log.levels.WARN)
      return
    end
    local lines = output.get_lines(0, cell.id)
    if not lines or #lines == 0 then
      vim.notify("NeoNotebook: no output for cell", vim.log.levels.INFO)
      return
    end
    local has_ansi, count = output.has_ansi(lines)
    if has_ansi then
      vim.notify("NeoNotebook: ANSI sequences found (" .. tostring(count) .. ")", vim.log.levels.INFO)
    else
      vim.notify("NeoNotebook: no ANSI sequences in output", vim.log.levels.WARN)
    end
  end, {})

  vim.api.nvim_create_user_command("PadDebug", function()
    local cfg = require("neo_notebooks").config
    local win = vim.api.nvim_win_get_width(0)
    local width = math.floor(win * (cfg.cell_width_ratio or 0.9))
    width = math.max(cfg.cell_min_width or 60, width)
    width = math.min(cfg.cell_max_width or win, width)
    width = math.min(width, win)
    local pad = math.max(0, math.floor((win - width) / 2))
    local text = vim.api.nvim_get_current_line():gsub(" ", "·")
    vim.notify(string.format("PadDebug: pad=%d col=%d line=%s", pad, vim.api.nvim_win_get_cursor(0)[2], text), vim.log.levels.INFO)
  end, {})

  vim.api.nvim_create_user_command("NeoNotebookAnsiSample", function()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1
    local cell = cells.get_cell_at_line(0, line)
    if not cell or not cell.id then
      vim.notify("NeoNotebook: no cell id found", vim.log.levels.WARN)
      return
    end
    output.show_inline(0, cell, {
      "\27[1;36mANSI Cyan Bold\27[0m and \27[33mYellow\27[0m text",
    })
  end, {})
end

return M
