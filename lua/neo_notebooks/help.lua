local nb = require("neo_notebooks")

local M = {}

local function open_help(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local width = math.min(vim.o.columns - 6, 80)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "single",
  })

  vim.api.nvim_win_set_option(win, "wrap", true)

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true })
end

function M.show()
  local maps = nb.config.keymaps or {}
  local lines = {
    "NeoNotebook help",
    "",
    "Commands:",
    "  :NeoNotebookCellRun        run current cell",
    "  :NeoNotebookCellRunAndNext run and create new cell",
    "  :NeoNotebookRunAll         run all code cells",
    "  :NeoNotebookRunAbove       run cells above",
    "  :NeoNotebookRunBelow       run cells below",
    "  :NeoNotebookMarkdownPreview preview markdown",
    "  :NeoNotebookCellList       list cells",
    "  :NeoNotebookStats          show stats",
    "  :NeoNotebookImportIpynb    import ipynb",
    "  :NeoNotebookImportJupytext import Jupytext py:percent",
    "  :NeoNotebookOpenJupytext   open Jupytext py:percent in notebook view",
    "  :NeoNotebookExportIpynb    export ipynb",
    "  :NeoNotebookOutputClear    clear output for cell",
    "  :NeoNotebookOutputClearAll clear output for all cells",
    "  :NeoNotebookOutputCollapseToggle toggle output collapse",
    "  :NeoNotebookOutputPrint    print output for cell",
    "  :NeoNotebookSnakeCell      insert/play snake; <leader> pause, <Esc>/game over deletes cell",
    "",
    "Keymaps:",
  }

  local function add(label, value)
    if value then
      table.insert(lines, string.format("  %s  %s", value, label))
    end
  end

  add("new code cell", maps.new_code)
  add("new markdown cell", maps.new_markdown)
  add("run cell", maps.run)
  add("run and next", maps.run_and_next)
  add("next cell", maps.next_cell)
  add("prev cell", maps.prev_cell)
  add("cell list", maps.cell_list)
  add("duplicate cell", maps.duplicate_cell)
  add("split cell", maps.split_cell)
  add("fold cell", maps.fold_cell)
  add("unfold cell", maps.unfold_cell)
  add("toggle fold", maps.toggle_fold)
  add("clear output", maps.clear_output)
  add("clear all output", maps.clear_all_output)
  add("delete cell", maps.delete_cell)
  add("yank cell", maps.yank_cell)
  add("move up", maps.move_up)
  add("move down", maps.move_down)
  add("run all", maps.run_all)
  add("restart", maps.restart)
  add("toggle output", maps.toggle_output)
  add("toggle output collapse", maps.toggle_output_collapse)
  add("select cell", maps.select_cell)
  add("stats", maps.stats)
  add("run above", maps.run_above)
  add("run below", maps.run_below)
  add("toggle auto render", maps.toggle_auto_render)
  add("toggle overlay", maps.toggle_overlay)
  add("snake game", maps.snake_game)

  open_help(lines)
end

return M
