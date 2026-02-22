# neo_notebooks

Experimental Neovim plugin that recreates core Jupyter-like behavior with cell markers, per-cell execution, and a simple virtual cell outline.

## Quick start

1. Add this repo to your Neovim runtime path or plugin manager.
2. In a buffer, define cells using markers like:

```python
# %% [code]
print("hello")

# %% [markdown]
# Title
```

3. Use commands:

- `:NeoNotebookCellNew [code|markdown]` inserts a new cell below the cursor.
- `:NeoNotebookCellToggleType` toggles the current cell type.
- `:NeoNotebookCellRun` executes the current code cell with a persistent Python session and shows output.
- `:NeoNotebookCellRunAndNext` runs the current cell and creates a new code cell below.
- `:NeoNotebookRender` redraws virtual cell borders.
- `:NeoNotebookCellDuplicate` duplicates the current cell.
- `:NeoNotebookCellSplit` splits the current cell at the cursor.
- `:NeoNotebookCellFold` folds the current cell.
- `:NeoNotebookCellUnfold` unfolds the current cell.
- `:NeoNotebookCellFoldToggle` toggles fold for the current cell.
- `:NeoNotebookOutputClear` clears inline output for the current cell.
- `:NeoNotebookOutputClearAll` clears inline output for all cells.
- `:NeoNotebookCellDelete` deletes the current cell.
- `:NeoNotebookCellYank` yanks the current cell to the default register.
- `:NeoNotebookCellMoveUp` moves the current cell up.
- `:NeoNotebookCellMoveDown` moves the current cell down.
- `:NeoNotebookRunAll` runs all code cells.
- `:NeoNotebookRestart` restarts the Python session and clears outputs.
- `:NeoNotebookOutputToggle` toggles output mode between inline and floating.
- `:NeoNotebookCellSelect` selects the current cell body.
- `:NeoNotebookStats` shows a cell count summary.
- `:NeoNotebookRunAbove` runs all code cells above the cursor.
- `:NeoNotebookRunBelow` runs all code cells below the cursor.
- `:NeoNotebookAutoRenderToggle` toggles auto-rendering.
- `:NeoNotebookHelp` shows a quick help window.
- `:NeoNotebookCellEdit` opens the current cell in a floating editor.
- `:NeoNotebookCellSave` saves the floating editor back to the buffer.
- `:NeoNotebookCellRunFromEditor` saves and runs the edited cell.
- `:NeoNotebookImportIpynb {path}` imports a `.ipynb` file.
- `:NeoNotebookOpenIpynb {path}` opens a `.ipynb` into a new buffer.
- `:NeoNotebookExportIpynb {path}` exports the current buffer to `.ipynb`.

## Configuration

```lua
require("neo_notebooks").setup({
  python_cmd = "python3",
  auto_render = true,
  output = "inline",
  filetypes = { "python" },
  require_markers = false,
  auto_insert_first_cell = true,
  overlay_preview = false,
  suppress_completion_in_markdown = true,
  auto_insert_on_jump = true,
  border_hl_code = "NeoNotebookBorderCode",
  border_hl_markdown = "NeoNotebookBorderMarkdown",
  show_cell_index = true,
  vertical_borders = true,
  cell_width_ratio = 0.9,
  cell_min_width = 60,
  cell_max_width = 140,
  keymaps = {
    new_code = "]c",
    new_markdown = "]m",
    run = "<leader>r",
    toggle = "<leader>m",
    preview = "<leader>p",
    run_and_next = "<S-CR>",
    next_cell = "<C-n>",
    prev_cell = "<C-p>",
    cell_list = "<leader>l",
    duplicate_cell = "<leader>yd",
    split_cell = "<leader>xs",
    fold_cell = "<leader>zf",
    unfold_cell = "<leader>zu",
    toggle_fold = "<leader>zz",
    clear_output = "<leader>co",
    clear_all_output = "<leader>cO",
    delete_cell = "<leader>dd",
    yank_cell = "<leader>yy",
    move_up = "<leader>mu",
    move_down = "<leader>md",
    run_all = "<leader>ra",
    restart = "<leader>rs",
    toggle_output = "<leader>tt",
    select_cell = "<leader>vs",
    stats = "<leader>ns",
    run_above = "<leader>rA",
    run_below = "<leader>rB",
    toggle_auto_render = "<leader>tr",
    toggle_overlay = "<leader>to",
    help = "<leader>nh",
    edit_cell = "<leader>ee",
    save_cell = "<leader>es",
    run_cell = "<leader>er",
  },
})
```

## Notes

- Cells are separated by lines like `# %% [code]` or `# %% [markdown]`.
- Virtual borders are rendered using virtual lines; output is inline by default.
- The last expression in a code cell is printed automatically (Jupyter-like).
- This is a minimal experimental baseline and intended to be expanded.

### Cell index cache

The plugin maintains a per-buffer cell index cache and rebuilds it on buffer changes to speed up lookups.
The cache stores both an ordered list and an ID map for O(1) access.
Each cell has a stable `cell_id` stored as an extmark on the marker line.

### Rich output (optional)

If `rich` is installed in your Python environment, the last expression in a cell is rendered using Rich.
You can toggle this at runtime inside a notebook:

```python
neo_rich(False)  # disable rich rendering
neo_rich(True)   # enable rich rendering
```

For pandas DataFrames/Series, Rich renders a table (limited to 20 rows/columns by default).
You can override limits:

```python
__neo_notebooks_rich_max_rows = 50
__neo_notebooks_rich_max_cols = 30
```

### Tests

Run tests in headless Neovim:

```
nvim --headless -u NONE -c \"lua dofile('tests/run.lua')\"
```

### Automatic first cell

When opening an empty `python` buffer, the plugin inserts a starter markdown cell:

```python
# %% [markdown]

```

### Shift+Enter behavior

Default `Shift+Enter` (`<S-CR>`) behavior:
- Markdown cell: create a new code cell below and enter it.
- Code cell: execute the cell, show output inline below it, create a new code cell, and enter it.

You can switch output style to a floating window with:

```lua
require("neo_notebooks").setup({ output = "float" })
```

### Markdown preview

Run `:NeoNotebookMarkdownPreview` in a markdown cell to open a floating preview window with markdown highlighting.

### Cell overlay preview (read-only)

Enable a floating, read-only overlay that mirrors the current cell:

```lua
require("neo_notebooks").setup({ overlay_preview = true })
```

You can toggle it on demand with `:NeoNotebookCellOverlayToggle`.

### Completion suppression in markdown cells

By default, completion popups are disabled while your cursor is inside a markdown cell:

```lua
require("neo_notebooks").setup({ suppress_completion_in_markdown = true })
```

This sets `vim.b.completion = false` when entering markdown cells and restores the previous value in code cells.

### Keymaps (defaults)

- `]c` new code cell below
- `]m` new markdown cell below
- `<leader>r` run current cell
- `<leader>m` toggle cell type
- `<leader>p` preview markdown cell
- `<S-CR>` run cell and create new code cell
- `<C-n>` next cell
- `<C-p>` previous cell
- `<leader>l` open cell list picker
- `<leader>yd` duplicate cell
- `<leader>xs` split cell at cursor
- `<leader>zf` fold current cell
- `<leader>zu` unfold current cell
- `<leader>zz` toggle fold for current cell
- `<leader>co` clear output for current cell
- `<leader>cO` clear output for all cells
- `<leader>dd` delete current cell
- `<leader>yy` yank current cell
- `<leader>mu` move cell up
- `<leader>md` move cell down
- `<leader>ra` run all code cells
- `<leader>rs` restart python session
- `<leader>tt` toggle output mode
- `<leader>vs` select current cell body
- `<leader>ns` show cell stats
- `<leader>rA` run all code cells above
- `<leader>rB` run all code cells below
- `<leader>tr` toggle auto-render
- `<leader>to` toggle overlay preview
- `<leader>nh` open help
- `<leader>ee` edit current cell in a floating window
- `<leader>es` save floating editor to buffer
- `<leader>er` run edited cell (save + execute)

### .ipynb import/export (basic)

Import:

```
:NeoNotebookImportIpynb path/to/notebook.ipynb
```

Export:

```
:NeoNotebookExportIpynb path/to/notebook.ipynb
```

Notes:
- This is a best-effort conversion of cell sources only (no outputs or rich metadata).
- Markdown and code cells are supported; other cell types are treated as code.

### Cell border color

By default, the plugin defines:
- `NeoNotebookBorderCode` (green)
- `NeoNotebookBorderMarkdown` (cyan)
- `NeoNotebookOutput` (purple)

You can override:

```lua
vim.api.nvim_set_hl(0, "NeoNotebookBorderCode", { fg = "#00ff00" })
vim.api.nvim_set_hl(0, "NeoNotebookBorderMarkdown", { fg = "#00ffff" })
vim.api.nvim_set_hl(0, "NeoNotebookOutput", { fg = "#a020f0" })
require("neo_notebooks").setup({
  border_hl_code = "NeoNotebookBorderCode",
  border_hl_markdown = "NeoNotebookBorderMarkdown",
})
```

### Cell index labels

Set `show_cell_index = false` to remove numeric labels from cell borders.

### Cell width

Cells are centered and responsive to window size:
- `cell_width_ratio` sets the width as a percentage of the window (default `0.9`).
- `cell_min_width` / `cell_max_width` clamp the width.

### Vertical borders

Set `vertical_borders = false` to disable left/right cell edges.

### Auto-insert on navigation

When enabled, jumping to another cell (next/prev/list) enters insert mode automatically.
Creating a new cell also enters insert mode by default.
