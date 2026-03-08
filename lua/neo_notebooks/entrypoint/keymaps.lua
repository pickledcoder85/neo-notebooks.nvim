local M = {}

function M.new(ctx)
  local nb = ctx.nb
  local cells = ctx.cells
  local markdown = ctx.markdown
  local output = ctx.output
  local overlay = ctx.overlay
  local navigation = ctx.navigation
  local actions = ctx.actions
  local run_all = ctx.run_all
  local session = ctx.session
  local stats = ctx.stats
  local run_subset = ctx.run_subset
  local help = ctx.help
  local editor = ctx.editor
  local scheduler = ctx.scheduler
  local snake = ctx.snake
  local should_enable = ctx.should_enable
  local render_if_enabled = ctx.render_if_enabled

  local function notify_guard_reason(bufnr)
    local reason = actions.consume_last_guard_reason(bufnr)
    if reason and reason ~= "" then
      vim.notify(reason, vim.log.levels.WARN)
    end
  end

  local function guard_expr(bufnr, fn)
    local keys = fn()
    if keys == "" then
      notify_guard_reason(bufnr)
    end
    return keys
  end

  local function clear_snake_keymaps(bufnr)
    bufnr = bufnr or 0
    local locked = vim.b[bufnr] and vim.b[bufnr].neo_notebooks_snake_locked_keys or {}
    for _, lhs in ipairs(locked) do
      pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
    end
    for _, lhs in ipairs({ "h", "j", "k", "l", "<Esc>", "<leader>" }) do
      pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
    end
    if vim.b[bufnr] then
      vim.b[bufnr].neo_notebooks_snake_locked_keys = nil
    end
  end

  local function set_snake_keymaps(bufnr)
    bufnr = bufnr or 0
    clear_snake_keymaps(bufnr)
    local opts = { noremap = true, silent = true, buffer = bufnr }
    local function turn(dir)
      local ok, err = snake.set_direction(bufnr, dir)
      if not ok and err then
        vim.notify("NeoNotebook: " .. err, vim.log.levels.WARN)
        return
      end
    end
    vim.keymap.set("n", "h", function()
      turn("left")
    end, opts)
    vim.keymap.set("n", "j", function()
      turn("down")
    end, opts)
    vim.keymap.set("n", "k", function()
      turn("up")
    end, opts)
    vim.keymap.set("n", "l", function()
      turn("right")
    end, opts)
    vim.keymap.set("n", "<Esc>", function()
      snake.stop(bufnr, { delete_cell = true, reason = "esc" })
    end, opts)
    vim.keymap.set("n", "<leader>", function()
      snake.toggle_pause(bufnr)
    end, opts)
    local locked = {
      "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
      "a", "b", "c", "d", "e", "f", "g", "i", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
      "A", "B", "C", "D", "E", "F", "G", "I", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
      ":", "/", "?", ".", ",", ";", "'", "\"", "<CR>", "<BS>", "<Del>",
      "$", "^", "%", "#", "*", "+", "-", "_", "=",
      "<C-n>", "<C-p>", "<S-CR>",
    }
    vim.b[bufnr].neo_notebooks_snake_locked_keys = locked
    for _, lhs in ipairs(locked) do
      vim.keymap.set("n", lhs, function()
        return
      end, opts)
    end
  end

  local function set_default_keymaps(bufnr)
    if nb.config.keymaps == false then
      return
    end

    bufnr = bufnr or 0
    if not should_enable(bufnr) then
      return
    end

    local maps = nb.config.keymaps or {}
    local opts = { noremap = true, silent = true, buffer = bufnr }

    if maps.new_code then
      vim.keymap.set("n", maps.new_code, function()
        local line = vim.api.nvim_win_get_cursor(0)[1] - 1
        local insert_line = cells.insert_cell_below(0, line, "code")
        vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
        actions.clamp_cursor_to_cell_left(0, { force = true })
        render_if_enabled(0)
        vim.cmd("startinsert")
      end, opts)
    end

    if maps.new_markdown then
      vim.keymap.set("n", maps.new_markdown, function()
        local line = vim.api.nvim_win_get_cursor(0)[1] - 1
        local insert_line = cells.insert_cell_below(0, line, "markdown")
        vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
        actions.clamp_cursor_to_cell_left(0, { force = true })
        render_if_enabled(0)
        vim.cmd("startinsert")
      end, opts)
    end

    if maps.run then
      vim.keymap.set("n", maps.run, function()
        vim.cmd("NeoNotebookCellRun")
      end, opts)
    end

    if maps.toggle then
      vim.keymap.set("n", maps.toggle, function()
        local line = vim.api.nvim_win_get_cursor(0)[1] - 1
        cells.toggle_cell_type(0, line)
        render_if_enabled(0)
      end, opts)
    end

    if maps.preview then
      vim.keymap.set("n", maps.preview, function()
        markdown.preview_cell(0)
      end, opts)
    end

    if maps.run_and_next then
      vim.keymap.set({ "n", "i" }, maps.run_and_next, function()
        vim.cmd("stopinsert")
        vim.cmd("NeoNotebookCellRunAndNext")
      end, opts)
    end

    if maps.next_cell then
      vim.keymap.set("n", maps.next_cell, function()
        navigation.next_cell(0)
      end, opts)
    end

    if maps.prev_cell then
      vim.keymap.set("n", maps.prev_cell, function()
        navigation.prev_cell(0)
      end, opts)
    end

    if maps.cell_list then
      vim.keymap.set("n", maps.cell_list, function()
        navigation.cell_list(0)
      end, opts)
    end

    if maps.duplicate_cell then
      vim.keymap.set("n", maps.duplicate_cell, function()
        actions.duplicate_cell(0)
      end, opts)
    end

    if maps.split_cell then
      vim.keymap.set("n", maps.split_cell, function()
        actions.split_cell(0)
      end, opts)
    end

    if maps.fold_cell then
      vim.keymap.set("n", maps.fold_cell, function()
        actions.fold_cell(0)
      end, opts)
    end

    if maps.unfold_cell then
      vim.keymap.set("n", maps.unfold_cell, function()
        actions.unfold_cell(0)
      end, opts)
    end

    if maps.toggle_fold then
      vim.keymap.set("n", maps.toggle_fold, function()
        actions.toggle_fold_cell(0)
      end, opts)
    end

    if maps.clear_output then
      vim.keymap.set("n", maps.clear_output, function()
        actions.clear_output(0)
      end, opts)
    end

    if maps.clear_image then
      vim.keymap.set("n", maps.clear_image, function()
        local line = vim.api.nvim_win_get_cursor(0)[1] - 1
        local cell = cells.get_cell_at_line(0, line)
        if cell and cell.id then
          output.clear_images(0, cell.id)
          scheduler.request_render(0, { immediate = true, cell_ids = { cell.id } })
        end
      end, opts)
    end

    if maps.clear_image_pane then
      vim.keymap.set("n", maps.clear_image_pane, function()
        require("neo_notebooks.image_pane").clear()
      end, opts)
    end

    if maps.image_pane_toggle_size then
      vim.keymap.set("n", maps.image_pane_toggle_size, function()
        require("neo_notebooks.image_pane").toggle_size()
      end, opts)
    end

    if maps.image_pane_collapse then
      vim.keymap.set("n", maps.image_pane_collapse, function()
        require("neo_notebooks.image_pane").collapse()
      end, opts)
    end

    if maps.image_pane_next then
      vim.keymap.set("n", maps.image_pane_next, function()
        require("neo_notebooks.image_pane").next()
      end, opts)
    end

    if maps.image_pane_prev then
      vim.keymap.set("n", maps.image_pane_prev, function()
        require("neo_notebooks.image_pane").prev()
      end, opts)
    end

    if maps.clear_all_output then
      vim.keymap.set("n", maps.clear_all_output, function()
        actions.clear_all_output(0)
      end, opts)
    end

    if maps.delete_cell then
      vim.keymap.set("n", maps.delete_cell, function()
        actions.delete_cell(0)
      end, opts)
    end

    if maps.yank_cell then
      vim.keymap.set("n", maps.yank_cell, function()
        actions.yank_cell(0)
      end, opts)
    end

    if maps.move_up then
      vim.keymap.set("n", maps.move_up, function()
        actions.move_cell_up(0, nil, vim.v.count1)
      end, opts)
    end

    if maps.move_down then
      vim.keymap.set("n", maps.move_down, function()
        actions.move_cell_down(0, nil, vim.v.count1)
      end, opts)
    end

    if maps.move_top then
      vim.keymap.set("n", maps.move_top, function()
        actions.move_cell_top(0)
      end, opts)
    end

    if maps.move_bottom then
      vim.keymap.set("n", maps.move_bottom, function()
        actions.move_cell_bottom(0)
      end, opts)
    end

    if maps.run_all then
      vim.keymap.set("n", maps.run_all, function()
        run_all.run_all(0)
      end, opts)
    end

    if maps.restart then
      vim.keymap.set("n", maps.restart, function()
        session.restart(0)
      end, opts)
    end

    if maps.toggle_output then
      vim.keymap.set("n", maps.toggle_output, function()
        actions.toggle_output_mode()
      end, opts)
    end

    if maps.toggle_output_collapse then
      vim.keymap.set("n", maps.toggle_output_collapse, function()
        actions.toggle_output_collapse(0)
      end, opts)
    end

    if maps.select_cell then
      vim.keymap.set("n", maps.select_cell, function()
        actions.select_cell(0)
      end, opts)
    end

    if maps.stats then
      vim.keymap.set("n", maps.stats, function()
        stats.show(0)
      end, opts)
    end

    if maps.run_above then
      vim.keymap.set("n", maps.run_above, function()
        run_subset.run_above(0)
      end, opts)
    end

    if maps.run_below then
      vim.keymap.set("n", maps.run_below, function()
        run_subset.run_below(0)
      end, opts)
    end

    if maps.toggle_auto_render then
      vim.keymap.set("n", maps.toggle_auto_render, function()
        actions.toggle_auto_render()
      end, opts)
    end

    if maps.toggle_overlay then
      vim.keymap.set("n", maps.toggle_overlay, function()
        overlay.toggle(0)
      end, opts)
    end

    if maps.help then
      vim.keymap.set("n", maps.help, function()
        help.show()
      end, opts)
    end

    if maps.edit_cell then
      vim.keymap.set("n", maps.edit_cell, function()
        editor.edit_cell(0)
      end, opts)
    end

    if maps.save_cell then
      vim.keymap.set("n", maps.save_cell, function()
        editor.save_current()
      end, opts)
    end

    if maps.run_cell then
      vim.keymap.set("n", maps.run_cell, function()
        editor.run_from_editor()
      end, opts)
    end

    if maps.snake_game then
      vim.keymap.set("n", maps.snake_game, function()
        vim.cmd("NeoNotebookSnakeCell")
      end, opts)
    end

    if nb.config.soft_contain then
      vim.keymap.set("n", "o", function()
        actions.open_line_below(bufnr)
      end, vim.tbl_extend("force", opts, { remap = true }))
      vim.keymap.set("n", "O", function()
        actions.open_line_above(bufnr)
      end, vim.tbl_extend("force", opts, { remap = true }))
      vim.keymap.set("n", "gg", function()
        actions.goto_cell_top(bufnr)
      end, opts)
      vim.keymap.set("n", "G", function()
        actions.goto_cell_bottom(bufnr)
      end, opts)
      if nb.config.contain_line_nav ~= false then
        vim.keymap.set("n", "j", function()
          actions.move_line_down_contained(bufnr, vim.v.count1)
        end, opts)
        vim.keymap.set("n", "k", function()
          actions.move_line_up_contained(bufnr, vim.v.count1)
        end, opts)
        vim.keymap.set("n", "_", function()
          actions.goto_line_first_nonblank_contained(bufnr)
        end, opts)
      end
      vim.keymap.set("n", "<CR>", function()
        actions.handle_enter_normal(bufnr)
      end, opts)
      vim.keymap.set("i", "<CR>", function()
        actions.handle_enter_insert(bufnr)
      end, { silent = true, buffer = bufnr })
      vim.keymap.set("i", "<BS>", function()
        return guard_expr(bufnr, function()
          return actions.guard_backspace_in_insert(bufnr)
        end)
      end, { silent = true, buffer = bufnr, expr = true })
      vim.keymap.set("i", "<Del>", function()
        return guard_expr(bufnr, function()
          return actions.guard_delete_in_insert(bufnr)
        end)
      end, { silent = true, buffer = bufnr, expr = true })
      vim.keymap.set("n", "dd", function()
        return guard_expr(bufnr, function()
          return actions.guard_delete_current_line(bufnr)
        end)
      end, { silent = true, buffer = bufnr, expr = true, replace_keycodes = false })
      vim.keymap.set("n", "d", function()
        actions.handle_delete_motion(bufnr)
        notify_guard_reason(bufnr)
      end, { silent = true, buffer = bufnr })
      vim.keymap.set("n", "p", function()
        actions.handle_paste_below(bufnr)
      end, opts)
      vim.keymap.set("n", "u", function()
        actions.handle_undo(bufnr, vim.v.count1)
      end, opts)
      vim.keymap.set("n", "x", function()
        return guard_expr(bufnr, function()
          return actions.guard_delete_char(bufnr)
        end)
      end, { silent = true, buffer = bufnr, expr = true, replace_keycodes = false })
      vim.keymap.set("n", "D", function()
        return guard_expr(bufnr, function()
          return actions.guard_delete_to_eol(bufnr)
        end)
      end, { silent = true, buffer = bufnr, expr = true, replace_keycodes = false })
      vim.keymap.set("x", "d", function()
        return guard_expr(bufnr, function()
          return actions.guard_visual_delete(bufnr)
        end)
      end, { silent = true, buffer = bufnr, expr = true, replace_keycodes = false })
    end
  end

  return {
    clear_snake_keymaps = clear_snake_keymaps,
    set_snake_keymaps = set_snake_keymaps,
    set_default_keymaps = set_default_keymaps,
  }
end

return M
