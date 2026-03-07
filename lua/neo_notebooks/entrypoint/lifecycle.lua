local M = {}

function M.register(ctx)
  local nb = ctx.nb
  local cells = ctx.cells
  local render = ctx.render
  local output = ctx.output
  local overlay = ctx.overlay
  local actions = ctx.actions
  local ipynb = ctx.ipynb
  local index = ctx.index
  local scheduler = ctx.scheduler
  local exec = ctx.exec

  local should_enable = ctx.should_enable
  local set_default_keymaps = ctx.set_default_keymaps
  local set_python_filetype = ctx.set_python_filetype
  local render_if_enabled = ctx.render_if_enabled
  local ensure_initial_markdown_cell = ctx.ensure_initial_markdown_cell
  local ensure_top_padding = ctx.ensure_top_padding
  local trim_cell_spacing = ctx.trim_cell_spacing
  local update_completion = ctx.update_completion
  local update_textwidth = ctx.update_textwidth
  local reset_undo_baseline = ctx.reset_undo_baseline

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    callback = function(args)
      render_if_enabled(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufReadPost", {
    pattern = "*.ipynb",
    callback = function(args)
      if not nb.config.auto_open_ipynb then
        return
      end
      if vim.b[args.buf].neo_notebooks_ipynb_opened then
        return
      end
      local path = vim.api.nvim_buf_get_name(args.buf)
      if path == "" then
        return
      end
      vim.b[args.buf].neo_notebooks_ipynb_opened = true
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(args.buf) then
          return
        end
        vim.b[args.buf].neo_notebooks_skip_initial = true
        vim.api.nvim_buf_set_option(args.buf, "buftype", "acwrite")
        vim.api.nvim_buf_set_option(args.buf, "swapfile", false)
        vim.api.nvim_buf_set_option(args.buf, "modifiable", true)
        vim.b[args.buf].neo_notebooks_is_ipynb = true
        vim.b[args.buf].neo_notebooks_enabled = true
        set_python_filetype(args.buf)
        local ok, err = ipynb.import_ipynb(path, args.buf)
        if not ok then
          vim.b[args.buf].neo_notebooks_skip_initial = false
          vim.notify(err or "Import failed", vim.log.levels.ERROR)
          return
        end
        ensure_top_padding(args.buf)
        reset_undo_baseline(args.buf)
        vim.b[args.buf].neo_notebooks_skip_initial = true
        set_default_keymaps(args.buf)
        index.mark_dirty(args.buf)
        index.attach(args.buf)
        render_if_enabled(args.buf)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    pattern = "*.ipynb",
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if path == "" then
        return
      end
      local ok, err = ipynb.export_ipynb(path, args.buf)
      if not ok then
        vim.notify(err or "Export failed", vim.log.levels.ERROR)
        return
      end
      vim.api.nvim_buf_set_option(args.buf, "modified", false)
      vim.notify("NeoNotebook: wrote " .. path, vim.log.levels.INFO)
    end,
  })

  vim.api.nvim_create_autocmd({ "FileType" }, {
    callback = function(args)
      if should_enable(args.buf) then
        ensure_initial_markdown_cell(args.buf)
        if nb.config.overlay_preview then
          overlay.enable(args.buf)
        end
        return
      end
      render.clear(args.buf)
      output.clear(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }, {
    callback = function(args)
      overlay.on_cursor_moved(args.buf)
      update_completion(args.buf)
      update_textwidth(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    callback = function(args)
      if should_enable(args.buf) then
        index.on_text_changed(args.buf)
        local dirty_cells = index.consume_dirty_cells(args.buf)
        local hint = index.consume_render_hint(args.buf)
        local insert_mode = vim.api.nvim_get_mode().mode:match("^i") ~= nil
        local immediate = hint == "immediate" or insert_mode
        if dirty_cells then
          scheduler.request_render(args.buf, { debounce_ms = immediate and 0 or 20, immediate = immediate, cell_ids = dirty_cells })
        else
          scheduler.request_render(args.buf, { debounce_ms = immediate and 0 or 20, immediate = immediate })
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "InsertLeave" }, {
    callback = function(args)
      if should_enable(args.buf) then
        actions.consume_pending_virtual_indent(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    callback = function(args)
      if should_enable(args.buf) and nb.config.auto_render then
        scheduler.request_render(args.buf, { immediate = true })
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave" }, {
    callback = function(args)
      if should_enable(args.buf) and nb.config.auto_render then
        scheduler.request_render(args.buf, { immediate = true })
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    callback = function(args)
      set_default_keymaps(args.buf)
      if should_enable(args.buf) then
        ensure_top_padding(args.buf)
        trim_cell_spacing(args.buf)
        index.mark_dirty(args.buf)
        index.attach(args.buf)
        if nb.config.auto_render then
          scheduler.request_render(args.buf, { immediate = true })
        end
        if nb.config.notebook_scrolloff and nb.config.notebook_scrolloff > 0 then
          vim.api.nvim_set_option_value("scrolloff", nb.config.notebook_scrolloff, { win = 0 })
        end

        local function jump_to_first_body()
          if not vim.api.nvim_buf_is_valid(args.buf) then
            return
          end
          local state = index.get(args.buf)
          for _, entry in ipairs(state.list) do
            if entry.border ~= false then
              local target = math.min(entry.start + 1, entry.finish)
              vim.api.nvim_win_set_cursor(0, { target + 1, 0 })
              return
            end
          end
        end

        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(args.buf) then
            return
          end
          local cur_line = vim.api.nvim_win_get_cursor(0)[1] - 1
          local cur_cell = cells.get_cell_at_line(args.buf, cur_line)
          if cur_cell and (cur_cell.border == false or cur_line == cur_cell.start) then
            jump_to_first_body()
            return
          end
          if not vim.b[args.buf].neo_notebooks_opened then
            vim.b[args.buf].neo_notebooks_opened = true
            jump_to_first_body()
          end
        end)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "WinEnter" }, {
    callback = function(args)
      if should_enable(args.buf) and nb.config.auto_render then
        scheduler.request_render(args.buf, { immediate = true })
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "*.nn",
    callback = function(args)
      vim.b[args.buf].neo_notebooks_enabled = true
      set_python_filetype(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "InsertEnter" }, {
    callback = function(args)
      if should_enable(args.buf) then
        if nb.config.strict_containment == "soft" or nb.config.strict_containment == true then
          actions.contain_insert_entry(args.buf)
        end
      end
      update_completion(args.buf)
      update_textwidth(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "InsertLeave" }, {
    callback = function(args)
      if not should_enable(args.buf) then
        return
      end
      vim.b[args.buf].neo_notebooks_pending_virtual_indent = nil
      trim_cell_spacing(args.buf)
      index.on_text_changed(args.buf)
      actions.clamp_cursor_to_cell_left(args.buf)
      scheduler.request_render(args.buf, { immediate = true })
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, {
    callback = function(args)
      overlay.disable(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout" }, {
    callback = function(args)
      scheduler.cancel(args.buf)
      exec.stop_session(args.buf)
      output.clear_all(args.buf)
    end,
  })
end

return M
