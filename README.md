# neo_notebooks

Experimental Neovim plugin that recreates core Jupyter-like behavior with cell markers, per-cell execution, and a simple virtual cell outline.

## Who this is for (and who it isn't)

This plugin is a good fit if:
- You prefer editing in Neovim but need a notebook-like workflow for exploration, MVPs, or personal projects.
- You want a lightweight, Neovim-native compromise before moving work into a more robust notebook stack.
- You value fast iteration, simple setup, and readable notebooks over full Jupyter feature parity.

This plugin may not be a fit if:
- You need full Jupyter kernel compatibility, rich outputs (plots/HTML/LaTeX/images), or collaborative notebook features.
- You rely on browser-based notebook UIs or multi-kernel workflows.

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
- `:NeoNotebookOutputCollapseToggle` toggles collapsed output for the current cell.
- `:NeoNotebookOutputPrint` prints the current cell output to `:messages`.
- Typed outputs are supported (text + image/png).
- `image_renderer = "auto" | "kitty" | "none"` controls image rendering backend.
- `image_protocol = "auto" | "kitty" | "none"` controls kitty graphics usage/detection.
- `image_render_target = "pane" | "inline"` controls whether images render in a right-side pane (default) or inline.
- `image_pane_tty = "/dev/pts/XX"` optional explicit TTY for the image pane. If unset and running inside tmux, a right split pane is created automatically.
- If no pane is configured, the plugin auto-creates a right tmux pane on first image render and reuses it for the rest of the session. Use `:NeoNotebookImagePaneReset` to force a new pane.
- If you are running inside tmux and Ghostty, set `image_protocol = "kitty"` if auto-detection doesn't pick it up.
- For tmux, enable passthrough so Kitty graphics reach Ghostty: `set -g allow-passthrough on`.
- `image_pane_tmux_percent = number` percent width for auto-created tmux image pane (default 25).
- `image_pane_spacing_lines = number` blank lines inserted between rendered images in the pane (default 1).
- `image_size_mode = "pane"|"default"` controls image sizing.
  - `"pane"` sizes pane-rendered images to the tmux pane using `pane_width`/`pane_height`.
  - `"default"` uses fixed defaults (`image_default_rows`/`image_default_cols`) for inline sizing.
- `image_pane_margin_cols = number` columns to subtract from pane width (default 2).
- `image_pane_margin_rows = number` rows to subtract from pane height (default 5).
- `image_pane_sizes = {25,33,50}` toggle sizes for `<leader>pt` (percent of window width).
- `image_pane_statusline = true` append an image pane size indicator to the statusline.
- `image_pane_tmp_dir = "/tmp/neo_notebooks-images"` directory for saved image files.
- `image_pane_mode = "page"|"stack"` set to `"page"` to show one image at a time.
- `image_pane_preserve_aspect = true` preserve image aspect ratio when fitting to pane.
- `image_pane_cell_ratio = 2.0` cell height/width ratio used for aspect correction.
- `image_max_rows = number` caps image height in rows (default 30).
- `image_default_rows = number` default image height in rows when no metadata is available (default 6).
- `image_default_cols = number` default image width in cols (default 12).
  - `image_fallback = "placeholder"` shows a notice when images cannot render.
  - `mpl_backend = "Agg"` forces a non-GUI backend for inline capture (prevents popup windows).
  - `plt.show()` is intercepted to signal an inline capture without a GUI popup.
- `:NeoNotebookCellDelete` deletes the current cell.
- `:NeoNotebookCellYank` yanks the current cell to the default register.
- `:NeoNotebookCellMoveUp` moves the current cell up.
- `:NeoNotebookCellMoveDown` moves the current cell down.
- `:NeoNotebookRunAll` runs all code cells.
- `:NeoNotebookRestart` restarts the Python session and clears outputs.
- `:NeoNotebookOutputToggle` toggles output mode between inline and floating.
- While a cell is executing, a spinner animates on the first inline output row.
- While a cell runs, an inline placeholder output shows `cell executing...`.
- After execution, inline output includes a right-aligned timing line (e.g. `[8.56ms]`).
- Moving cells preserves outputs by stable cell ID.
- `:NeoNotebookCellSelect` selects the current cell body.
- `:NeoNotebookStats` shows a cell count summary.
- `:NeoNotebookRunAbove` runs all code cells above the cursor.
- `:NeoNotebookRunBelow` runs all code cells below the cursor.
- `:NeoNotebookAutoRenderToggle` toggles auto-rendering.
- `:NeoNotebookCellIndexToggle` toggles numeric cell index labels on borders.
- `:NeoNotebookHelp` shows a quick help window.
- `:NeoNotebookCellEdit` opens the current cell in a floating editor.
- `:NeoNotebookCellSave` saves the floating editor back to the buffer.
- `:NeoNotebookCellRunFromEditor` saves and runs the edited cell.
- `:NeoNotebookSnakeCell` inserts a new code cell and starts a mini inline snake mode (auto-moving snake; fixed default board `25x10`; `h/j/k/l` turns direction; `<leader>` pauses/resumes; `<Esc>` or game over deletes the snake cell and exits mode).
- Snake colors are themed via highlight groups: `NeoNotebookSnakeBorder` (default white), `NeoNotebookSnakeHead` (`@`, default yellow), `NeoNotebookSnakeBody` (`o`, default green), `NeoNotebookSnakeApple` (`*`, default red).
- `:NeoNotebookImportIpynb {path}` imports a `.ipynb` file.
- `:NeoNotebookOpenIpynb {path}` opens a `.ipynb` into a new buffer.
- `:NeoNotebookExportIpynb {path}` exports the current buffer to `.ipynb`.

## Configuration

```lua
require("neo_notebooks").setup({
  python_cmd = "python3",
  auto_render = true,
  output = "inline",
  image_renderer = "auto",
  image_protocol = "auto",
  image_render_target = "pane",
  image_pane_tty = nil,
  image_pane_tmux_percent = 25,
  image_pane_spacing_lines = 1,
  image_size_mode = "pane",
  image_pane_margin_cols = 2,
  image_pane_margin_rows = 5,
  image_pane_sizes = { 25, 33, 50 },
  image_pane_statusline = true,
  image_pane_tmp_dir = "/tmp/neo_notebooks-images",
  image_pane_mode = "page",
  image_pane_preserve_aspect = true,
  image_pane_cell_ratio = 2.0,
  image_max_rows = 30,
  image_default_rows = 6,
  image_default_cols = 12,
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
    move_up = "<M-k>",
    move_down = "<M-j>",
    move_top = "<leader>mG",
    move_bottom = "<leader>mgg",
    run_all = "<leader>ra",
    restart = "<leader>rs",
    toggle_output = "<leader>tt",
    toggle_output_collapse = "<leader>of",
    select_cell = "<leader>vs",
    stats = "<leader>ns",
    run_above = "<leader>rk",
    run_below = "<leader>rj",
    toggle_auto_render = "<leader>tr",
    toggle_overlay = "<leader>to",
    help = "<leader>nh",
    edit_cell = "<leader>ee",
    save_cell = "<leader>es",
    run_cell = "<leader>er",
    snake_game = "<leader>sg",
  },
})
```

## Notes

- Cells are separated by lines like `# %% [code]` or `# %% [markdown]`.
- Virtual borders are rendered using virtual lines; output is inline by default.
- The last expression in a code cell is printed automatically (Jupyter-like).
- Cell execution is serialized per buffer via an internal FIFO queue (including
  run-all/above/below), so outputs land in predictable order.
- Notebook buffers set `scrolloff` to keep a few lines visible below the cursor.
- This is a minimal experimental baseline and intended to be expanded.

### Cell index cache

The plugin maintains a per-buffer cell index cache with lazy invalidation.
Buffer mutations mark the cache as dirty, and reads rebuild only when needed.
The cache also tracks buffer `changedtick` to avoid stale reads.
The cache stores both an ordered list and an ID map for O(1) access.
Each cell has a stable `cell_id` stored as an extmark on the marker line.

### Render scheduling

High-frequency updates (text changes and execution spinner ticks) are coalesced by a
small per-buffer render scheduler. This reduces redundant full redraws during bursts
of edits while keeping output and borders in sync.

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
- If the trailing code cell is empty, it will not create another empty trailing code cell.

You can switch output style to a floating window with:

```lua
require("neo_notebooks").setup({ output = "float" })
```

### Markdown preview

Run `:NeoNotebookMarkdownPreview` in a markdown cell to open a floating preview window with markdown highlighting.
Inline markdown cells also get lightweight virtual formatting for headings and emphasis/code spans when not actively edited.
For fenced markdown blocks tagged as `python` (```python ... ```), NeoNotebooks uses Tree-sitter token captures when available; it falls back to raw-block highlighting if parser/query support is unavailable.

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

### blink.cmp popup suppression in notebooks

If you use `blink.cmp` and want to keep completion while disabling the popup menu in notebooks, add this to your `blink.cmp` config:

```lua
completion = {
  menu = {
    auto_show = require("neo_notebooks").blink_cmp_auto_show,
  },
}
```

If you want to disable completion entirely in notebooks, set:

```lua
require("neo_notebooks").setup({ suppress_completion_popup = true })
```

### Keymaps (defaults)

- `<leader><leader>ac` new code cell below
- `<leader><leader>am` new markdown cell below
- `<leader>r` run current cell
- `<leader>tc` toggle cell type
- `<S-CR>` run cell and create new code cell
- `<C-n>` next cell
- `<C-p>` previous cell
- `<leader>yd` duplicate cell
- `<leader>xs` split cell at cursor
- `<leader>zf` fold current cell
- `<leader>zu` unfold current cell
- `<leader>zz` toggle fold for current cell
- `<leader>co` clear output for current cell
- `<leader>cO` clear output for all cells
- `<leader>oi` clear image output for current cell
- `<leader>oI` clear image pane
- `<leader>pt` toggle image pane size (25/33/50% default)
- `<leader>pc` collapse/close image pane
- `<leader>pn` next image (page mode)
- `<leader>pp` previous image (page mode)
- `<leader>dd` delete current cell
- `<leader>yy` yank current cell
- `<M-k>` move cell up (accepts counts, e.g. `3<M-k>`)
- `<M-j>` move cell down (accepts counts, e.g. `2<M-j>`)
- `<leader>mG` move cell to top
- `<leader>mgg` move cell to bottom
- `j` / `k` stay inside the active cell body when `soft_contain=true` and `contain_line_nav=true`
- `u` (undo) preserves native undo behavior and then re-clamps cursor within current cell bounds
  (use `<C-n>` / `<C-p>` to move between cells)
- `<leader>sg` starts snake mode by creating a new code cell below the current cell

If you use a custom statusline (e.g. lualine), add the component:

```
require("neo_notebooks.image_pane").statusline()
```

Note: `<M-...>` means the Meta key (typically `Alt` on most keyboards).

When the pane is collapsed with `<leader>pc`, new images are saved to disk and not auto-rendered until the pane is reopened (use `<leader>pt` or `:NeoNotebookImagePaneTest` to reopen).
- `<leader>ra` run all code cells
- `<leader>rs` restart python session
- `<leader>vs` select current cell body
- `<leader>ns` show cell stats
- `<leader>rk` run all code cells above
- `<leader>rj` run current + below code cells
- `<leader>tr` toggle auto-render

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
- `.ipynb` metadata, execution counts, and cell outputs are preserved on import/export.
- Existing outputs are rendered on import for code cells.
- Markdown and code cells are supported; other cell types are treated as code.
- Import drops a leading blank code cell if it appears before the first markdown cell.
- After `.ipynb` import/open, undo baseline is reset so extra `u` does not revert to raw JSON import state.

### Filetypes

- `*.nn` files are detected as Python for LSP/syntax and opt-in to NeoNotebook via a buffer flag.
- `*.ipynb` files auto-open into a Python buffer (converted to marker format) when
  `auto_open_ipynb = true`.
- Saving (`:w`) in an `.ipynb` buffer exports the current cells back to the `.ipynb` file.

Note: `top_padding` inserts real blank lines at the top of the buffer on first open to keep the top border visible.

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
