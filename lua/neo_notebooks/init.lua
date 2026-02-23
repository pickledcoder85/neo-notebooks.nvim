local M = {}

M.config = {
  python_cmd = "python3",
  auto_render = true,
  output = "inline",
  filetypes = { "neo_notebook", "ipynb" },
  auto_open_ipynb = true,
  require_markers = false,
  auto_insert_first_cell = true,
  overlay_preview = false,
  suppress_completion_in_markdown = true,
  auto_insert_on_jump = false,
  border_hl_code = "NeoNotebookBorderCode",
  border_hl_markdown = "NeoNotebookBorderMarkdown",
  show_cell_index = true,
  vertical_borders = true,
  cell_width_ratio = 0.9,
  cell_min_width = 60,
  cell_max_width = 140,
  top_padding = 1,
  trim_cell_spacing = true,
  cell_gap_lines = 1,
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
    delete_cell = "<leader>dd",
    yank_cell = "<leader>yy",
    move_up = "<M-k>",
    move_down = "<M-j>",
    move_top = "<leader>mG",
    move_bottom = "<leader>mgg",
    run_all = "<leader>ra",
    restart = "<leader>rs",
    select_cell = "<leader>vs",
    stats = "<leader>ns",
    run_above = "<leader>rA",
    run_below = "<leader>rB",
    toggle_auto_render = "<leader>tr",
    toggle_overlay = nil,
    help = nil,
    edit_cell = nil,
    save_cell = nil,
    run_cell = nil,
  },
}

function M.setup(opts)
  opts = opts or {}
  if opts.keymaps and M.config.keymaps ~= false then
    opts.keymaps = vim.tbl_extend("force", M.config.keymaps or {}, opts.keymaps)
  end
  M.config = vim.tbl_extend("force", M.config, opts)
  if M._on_setup then
    M._on_setup()
  end
end

return M
