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
  keymaps = {
    new_code = "]c",
    new_markdown = "]m",
    run = "<leader>r",
    toggle = "<leader>m",
    preview = "<leader>p",
    run_and_next = "<S-CR>",
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

### Keymaps (defaults)

- `]c` new code cell below
- `]m` new markdown cell below
- `<leader>r` run current cell
- `<leader>m` toggle cell type
- `<leader>p` preview markdown cell
- `<S-CR>` run cell and create new code cell
