local M = {}

function M.setup(opts)
  local nb = require("neo_notebooks")
  local cells = require("neo_notebooks.cells")
  local render = require("neo_notebooks.render")
  local exec = require("neo_notebooks.exec")
  local markdown = require("neo_notebooks.markdown")
  local output = require("neo_notebooks.output")
  local overlay = require("neo_notebooks.overlay")
  local navigation = require("neo_notebooks.navigation")
  local actions = require("neo_notebooks.actions")
  local ipynb = require("neo_notebooks.ipynb")
  local run_all = require("neo_notebooks.run_all")
  local session = require("neo_notebooks.session")
  local stats = require("neo_notebooks.stats")
  local run_subset = require("neo_notebooks.run_subset")
  local help = require("neo_notebooks.help")
  local editor = require("neo_notebooks.editor")
  local index = require("neo_notebooks.index")
  local scheduler = require("neo_notebooks.scheduler")
  local snake = require("neo_notebooks.snake")

  local keymaps_api = require("neo_notebooks.entrypoint.keymaps").new({
    nb = nb,
    cells = cells,
    markdown = markdown,
    output = output,
    overlay = overlay,
    navigation = navigation,
    actions = actions,
    run_all = run_all,
    session = session,
    stats = stats,
    run_subset = run_subset,
    help = help,
    editor = editor,
    scheduler = scheduler,
    snake = snake,
    should_enable = opts.should_enable,
    render_if_enabled = opts.render_if_enabled,
  })

  require("neo_notebooks.entrypoint.commands").register({
    nb = nb,
    cells = cells,
    render = render,
    exec = exec,
    markdown = markdown,
    output = output,
    overlay = overlay,
    navigation = navigation,
    actions = actions,
    ipynb = ipynb,
    run_all = run_all,
    session = session,
    stats = stats,
    run_subset = run_subset,
    help = help,
    editor = editor,
    index = index,
    scheduler = scheduler,
    snake = snake,
    set_python_filetype = opts.set_python_filetype,
    should_enable = opts.should_enable,
    ensure_top_padding = opts.ensure_top_padding,
    render_if_enabled = opts.render_if_enabled,
    reset_undo_baseline = opts.reset_undo_baseline,
    set_default_keymaps = keymaps_api.set_default_keymaps,
    set_snake_keymaps = keymaps_api.set_snake_keymaps,
    clear_snake_keymaps = keymaps_api.clear_snake_keymaps,
  })

  require("neo_notebooks.entrypoint.lifecycle").register({
    nb = nb,
    cells = cells,
    render = render,
    output = output,
    overlay = overlay,
    actions = actions,
    ipynb = ipynb,
    index = index,
    scheduler = scheduler,
    exec = exec,
    should_enable = opts.should_enable,
    set_default_keymaps = keymaps_api.set_default_keymaps,
    set_python_filetype = opts.set_python_filetype,
    render_if_enabled = opts.render_if_enabled,
    ensure_initial_markdown_cell = opts.ensure_initial_markdown_cell,
    ensure_top_padding = opts.ensure_top_padding,
    trim_cell_spacing = opts.trim_cell_spacing,
    update_completion = opts.update_completion,
    update_textwidth = opts.update_textwidth,
    reset_undo_baseline = opts.reset_undo_baseline,
  })

  return keymaps_api
end

return M
