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
- `:NeoNotebookCellDelete` deletes the current cell.
- `:NeoNotebookRunAll` runs all code cells.
- `:NeoNotebookRestart` restarts the Python session and clears outputs.
- `:NeoNotebookImportIpynb {path}` imports a `.ipynb` file.
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
    toggle_fold = "<leader>zz",
    clear_output = "<leader>co",
    delete_cell = "<leader>dd",
    run_all = "<leader>ra",
    restart = "<leader>rs",
  },
})
```

## Notes

- Cells are separated by lines like `# %% [code]` or `# %% [markdown]`.
- Virtual borders are rendered using virtual lines; output is inline by default.
- The last expression in a code cell is printed automatically (Jupyter-like).
- This is a minimal experimental baseline and intended to be expanded.

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
- `]n` next cell
- `[n` previous cell
- `<leader>l` open cell list picker
- `<leader>yd` duplicate cell
- `<leader>xs` split cell at cursor
- `<leader>zf` fold current cell
- `<leader>zu` unfold current cell
- `<leader>zz` toggle fold for current cell
- `<leader>co` clear output for current cell
- `<leader>dd` delete current cell
- `<leader>ra` run all code cells
- `<leader>rs` restart python session

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

By default, the plugin defines `NeoNotebookBorder` as green. You can override:

```lua
vim.api.nvim_set_hl(0, "NeoNotebookBorder", { fg = "#00ff00" })
require("neo_notebooks").setup({ border_hl = "NeoNotebookBorder" })
```

### Auto-insert on navigation

When enabled, jumping to another cell (next/prev/list) enters insert mode automatically.
Creating a new cell also enters insert mode by default.
