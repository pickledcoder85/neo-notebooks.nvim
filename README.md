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
- `:NeoNotebookRender` redraws virtual cell borders.

## Configuration

```lua
require("neo_notebooks").setup({
  python_cmd = "python3",
  auto_render = true,
  filetypes = { "python" },
  require_markers = false,
  keymaps = {
    new_code = "]c",
    new_markdown = "]m",
    run = "<leader>r",
    toggle = "<leader>m",
  },
})
```

## Notes

- Cells are separated by lines like `# %% [code]` or `# %% [markdown]`.
- Virtual borders are rendered using virtual lines; output appears in a floating window.
- The last expression in a code cell is printed automatically (Jupyter-like).
- This is a minimal experimental baseline and intended to be expanded.

### Keymaps (defaults)

- `]c` new code cell below
- `]m` new markdown cell below
- `<leader>r` run current cell
- `<leader>m` toggle cell type
