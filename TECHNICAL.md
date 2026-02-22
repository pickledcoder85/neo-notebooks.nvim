# Technical Notes

This document summarizes implementation choices and the evolution of core features.

## Architecture overview

- `plugin/neo_notebooks.lua`
  - Registers user commands.
  - Sets buffer-local keymaps.
  - Runs auto-render via autocommands.
  - Stops Python sessions when buffers are wiped.
- `lua/neo_notebooks/cells.lua`
  - Parses cell markers (`# %% [code|markdown]`).
  - Identifies the current cell and inserts new cells.
- `lua/neo_notebooks/render.lua`
  - Draws virtual borders around cells using `virt_lines`.
  - Adds a virtual label indicating cell type.
- `lua/neo_notebooks/exec.lua`
  - Manages a persistent Python process per buffer.
  - Executes cell code and collects output.
  - Displays output in a floating window.
- `lua/neo_notebooks/markdown.lua`
  - Opens a markdown preview window for markdown cells.
  - Uses a scratch buffer with `filetype=markdown` for syntax highlighting.
- `lua/neo_notebooks/output.lua`
  - Manages inline output rendering via extmarks.
- `lua/neo_notebooks/overlay.lua`
  - Provides a read-only floating overlay that mirrors the current cell.

## Execution model

- Each buffer has a dedicated Python process started with `python -u -c <server>`.
- The Lua side sends JSON lines: `{ "id": n, "code": "..." }`.
- The Python side executes code in a shared `globals_dict` so state persists across cells.
- If the last statement is an expression, it is evaluated and printed (Jupyter-like).

## Output handling

- Output defaults to inline `virt_lines` under the cell.
- Floating output is still available by setting `output = "float"`.
- Floating output buffers are `nofile` and `bufhidden=wipe` and close on `q` or `<Esc>`.

## Markdown preview

- `:NeoNotebookMarkdownPreview` opens a centered floating window.
- Markdown is highlighted using Neovim's `markdown` filetype.
- Font sizes are not changed (Neovim does not support per-heading font sizes in a single buffer).

## Cell overlay preview

- The overlay is a scratch floating window that mirrors the current cell's lines.
- It is read-only and updates on cursor and text changes.
- The overlay is optional and can be toggled per buffer.

## Completion suppression in markdown cells

- When enabled, the plugin sets `vim.b.completion = false` inside markdown cells.
- The previous buffer-local completion setting is restored when returning to code cells.

## Cell border highlighting

- Borders use `border_hl` (default `NeoNotebookBorder`).
- The default highlight is defined in `plugin/neo_notebooks_colors.lua`.

## Navigation helpers

- `NeoNotebookCellNext` / `NeoNotebookCellPrev` move between cell headers.
- `NeoNotebookCellList` opens a picker to jump to a cell.
- When `auto_insert_on_jump` is enabled, navigation enters insert mode.

## Cell actions

- Duplicate: inserts a copy of the current cell below.
- Split: inserts a new cell marker at the cursor to split the cell.
- Fold/Unfold: uses manual folds for the current cell range.
- Toggle fold: opens or closes the current cell fold depending on state.
- Clear output: removes inline output extmarks for the current cell.
- Delete: removes the current cell from the buffer.
- Clear all output: removes inline output for all cells.
- Yank: copies the current cell to the default register.
- Move up/down: swaps the current cell with the previous/next cell.

## Run all and session control

- `NeoNotebookRunAll` executes all code cells in order.
- `NeoNotebookRestart` stops the Python session and clears outputs.

## Cell labels

- Borders can include a numeric cell index when `show_cell_index = true`.

## Cell list enhancements

- Cell list entries include line numbers.
- Selecting a cell centers the view.

## .ipynb import/export

- Import reads `.ipynb` JSON and converts cells to marker format.
- Export writes a minimal `.ipynb` with cell sources (no outputs).

## Auto-render and keymaps

- Auto-render is gated by:
  - `filetypes` (default `{ "python" }`).
  - Optional `require_markers` to render only when markers are present.
- Keymaps are buffer-local and only set when buffers pass the gating rules.

## Automatic first cell

- On `FileType` for eligible buffers, if the buffer is empty and has no markers,
  the plugin inserts `# %% [markdown]` and moves the cursor to the empty line below.

## Future work

- Add a proper markdown renderer for headings/emphasis.
- Provide navigation and cell list UI.
- Add `.ipynb` import/export.
- Add Lua tests for parsing and execution.
