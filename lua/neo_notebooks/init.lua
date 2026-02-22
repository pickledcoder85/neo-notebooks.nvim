local M = {}

M.config = {
  python_cmd = "python3",
  auto_render = true,
  output = "inline",
  filetypes = { "python" },
  require_markers = false,
  auto_insert_first_cell = true,
  overlay_preview = false,
  suppress_completion_in_markdown = true,
  auto_insert_on_jump = true,
  border_hl = "NeoNotebookBorder",
  keymaps = {
    new_code = "]c",
    new_markdown = "]m",
    run = "<leader>r",
    toggle = "<leader>m",
    preview = "<leader>p",
    run_and_next = "<S-CR>",
    next_cell = "]n",
    prev_cell = "[n",
    cell_list = "<leader>l",
    duplicate_cell = "<leader>yd",
    split_cell = "<leader>xs",
    fold_cell = "<leader>zf",
    unfold_cell = "<leader>zu",
    clear_output = "<leader>co",
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
