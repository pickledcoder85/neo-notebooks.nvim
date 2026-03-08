local M = {}

M.config = {
  python_cmd = "python3",
  auto_render = true,
  output = "inline",
  image_renderer = "auto",
  image_protocol = "auto",
  image_max_rows = 30,
  image_default_rows = 6,
  image_default_cols = 12,
  image_render_target = "pane",
  image_pane_tty = nil,
  image_pane_tmux_percent = 25,
  image_pane_spacing_lines = 1,
  image_pane_sizes = { 25, 33, 50 },
  image_size_mode = "pane",
  image_pane_margin_cols = 2,
  image_pane_margin_rows = 5,
  image_pane_tmp_dir = "/tmp/neo_notebooks-images",
  image_pane_mode = "page",
  image_pane_preserve_aspect = true,
  image_pane_cell_ratio = 2.0,
  image_pane_statusline = true,
  kernel_status_virtual = false,
  image_fallback = "placeholder",
  mpl_backend = "Agg",
  filetypes = { "neo_notebook", "ipynb" },
  auto_open_ipynb = true,
  require_markers = false,
  auto_insert_first_cell = true,
  overlay_preview = false,
  suppress_completion_in_markdown = true,
  suppress_completion_popup = false,
  auto_insert_on_jump = false,
  border_hl_code = "NeoNotebookBorderCode",
  border_hl_markdown = "NeoNotebookBorderMarkdown",
  show_cell_index = true,
  vertical_borders = true,
  cell_width_ratio = 0.75,
  cell_min_width = 60,
  cell_max_width = 140,
  top_padding = 1,
  trim_cell_spacing = true,
  cell_gap_lines = 1,
  soft_contain = true,
  strict_containment = "soft",
  contain_line_nav = true,
  textwidth_in_cells = true,
  notebook_scrolloff = 5,
  interrupt_on_rerun = true,
  skip_unchanged_rerun = true,
  kernel_recovery_retries = 1,
  keymaps = {
    new_code = "<leader><leader>ac",
    new_markdown = "<leader><leader>am",
    run = "<leader>r",
    toggle = "<leader>tc",
    run_and_next = "<S-CR>",
    next_cell = "<C-n>",
    prev_cell = "<C-p>",
    duplicate_cell = "<leader>yd",
    split_cell = "<leader>xs",
    fold_cell = "<leader>zf",
    unfold_cell = "<leader>zu",
    toggle_fold = "<leader>zz",
    clear_output = "<leader>co",
    clear_all_output = "<leader>cO",
    toggle_output_collapse = "<leader>of",
    clear_image = "<leader>oi",
    clear_image_pane = "<leader>oI",
    image_pane_toggle_size = "<leader>pt",
    image_pane_collapse = "<leader>pc",
    image_pane_next = "<leader>pn",
    image_pane_prev = "<leader>pp",
    delete_cell = "<leader>dd",
    yank_cell = "<leader>yy",
    move_up = "<M-k>",
    move_down = "<M-j>",
    move_top = "<leader>mG",
    move_bottom = "<leader>mgg",
    run_all = "<leader>ra",
    restart = "<leader>rs",
    kernel_restart = "<leader>kr",
    kernel_interrupt = "<leader>ki",
    kernel_stop = "<leader>ks",
    kernel_pause = "<leader>kp",
    kernel_status = "<leader>kk",
    select_cell = "<leader>vs",
    stats = "<leader>ns",
    run_above = "<leader>rk",
    run_below = "<leader>rj",
    toggle_auto_render = "<leader>tr",
    toggle_overlay = nil,
    help = nil,
    edit_cell = nil,
    save_cell = nil,
    run_cell = nil,
    snake_game = "<leader>sg",
  },
}

function M.setup(opts)
  opts = opts or {}
  if opts.keymaps and M.config.keymaps ~= false then
    opts.keymaps = vim.tbl_extend("force", M.config.keymaps or {}, opts.keymaps)
  end
  for key, value in pairs(opts) do
    M.config[key] = value
  end
  if M.config.image_pane_statusline then
    if not _G.NeoNotebookImagePaneStatus then
      _G.NeoNotebookImagePaneStatus = function()
        return require("neo_notebooks.image_pane").statusline()
      end
    end
    if not vim.g.neo_notebooks_statusline_added then
      vim.g.neo_notebooks_statusline_added = true
      local marker = "NeoNotebookImagePaneStatus"
      if vim.o.statusline and not vim.o.statusline:find(marker, 1, true) then
        vim.o.statusline = vim.o.statusline .. " %{v:lua.NeoNotebookImagePaneStatus()}"
      end
    end
  end
  if M._on_setup then
    M._on_setup()
  end
end

function M.is_notebook_buf(bufnr)
  bufnr = bufnr or 0
  if vim.b[bufnr] and vim.b[bufnr].neo_notebooks_enabled then
    return true
  end
  local allowed = M.config.filetypes
  if allowed and #allowed > 0 then
    local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    local ok = false
    for _, item in ipairs(allowed) do
      if ft == item then
        ok = true
        break
      end
    end
    if not ok then
      return false
    end
  end
  if M.config.require_markers then
    local cells = require("neo_notebooks.cells")
    return cells.has_markers(bufnr)
  end
  return true
end

function M.blink_cmp_auto_show(ctx)
  local bufnr = (ctx and ctx.bufnr) or 0
  return not M.is_notebook_buf(bufnr)
end

function M.kernel_status(bufnr)
  bufnr = bufnr or 0
  local ok_exec, exec = pcall(require, "neo_notebooks.exec")
  if not ok_exec or not exec or type(exec.get_session_state) ~= "function" then
    return "stopped"
  end
  local state = exec.get_session_state(bufnr)
  if not state or not state.state then
    return "stopped"
  end
  if state.state == "stopped" then
    return "stopped"
  end
  if state.paused then
    return "paused"
  end
  if state.state == "idle" then
    return "ok"
  end
  return state.state
end

return M
