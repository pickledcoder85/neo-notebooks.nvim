# Technical Notes

This document summarizes implementation choices and the evolution of core features.

## Documentation gate

- Any merge into `main` must reconcile `README.md`, `TODO.md`, and `TECHNICAL.md` for
  behavior/config/architecture changes.

## Architecture overview

- `plugin/neo_notebooks.lua`
  - Registers user commands.
  - Sets buffer-local keymaps.
  - Runs auto-render via autocommands.
  - Stops Python sessions when buffers are wiped.
- `lua/neo_notebooks/containment.lua`
  - Canonical cursor/cell geometry helper.
  - Computes active cell identity, editable body bounds, and protected floor.
- `lua/neo_notebooks/policy.lua`
  - Central policy engine for edit/navigation guards.
  - Decides allow/redirect/block for Enter, delete, and protected-line operations.
- `lua/neo_notebooks/cells.lua`
  - Parses cell markers (`# %% [code|markdown]`).
  - Identifies the current cell and inserts new cells.
- `lua/neo_notebooks/render.lua`
  - Draws virtual borders around cells using `virt_lines`.
  - Adds a virtual label indicating cell type.
- `lua/neo_notebooks/exec.lua`
  - Manages a persistent Python process per buffer.
  - Executes cell code and collects output.
  - Dispatches output to inline or floating renderers.
- `lua/neo_notebooks/markdown.lua`
  - Opens a markdown preview window for markdown cells.
  - Uses a scratch buffer with `filetype=markdown` for syntax highlighting.
- `lua/neo_notebooks/output.lua`
  - Stores inline output per cell ID and triggers re-rendering.
- `lua/neo_notebooks/overlay.lua`
  - Provides a read-only floating overlay that mirrors the current cell.

## Execution model

- Each buffer has a dedicated Python process started with `python -u -c <server>`.
- The Lua side sends JSON lines: `{ "id": n, "code": "..." }`.
- The Python side executes code in a shared `globals_dict` so state persists across cells.
- If the last statement is an expression, it is evaluated and printed (Jupyter-like).
- A per-buffer FIFO queue in `exec.lua` serializes requests so only one cell executes
  at a time; the next queued request starts when the previous response is handled.
- If a cell is re-run with unchanged code, execution can be skipped. If the code
  has changed and `interrupt_on_rerun` is enabled, the active request is interrupted
  and the new run starts immediately.

## Output handling

- Output defaults to inline `virt_lines` under the cell.
- Floating output is still available by setting `output = "float"`.
- Floating output buffers are `nofile` and `bufhidden=wipe` and close on `q` or `<Esc>`.
- While a cell is executing, a spinner is rendered on the first inline output row.
- While a cell runs, the output area shows a placeholder line.
- After execution, the inline output prepends a right-aligned timing line.
- Execution duration is measured around the request/response boundary and stored per cell ID.
- Spinner frames request immediate renders to avoid dropped updates.

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
- Clear output: clears stored output for the current cell and re-renders.
- Delete: removes the current cell from the buffer.
- Clear all output: removes inline output for all cells.
- Yank: copies the current cell to the default register.
- Move up/down: swaps the current cell with the previous/next cell while preserving outputs by cell ID.
- Select: enters visual line mode and selects the current cell body.
- Move to top/bottom: relocates the current cell to the start or end of the notebook while preserving outputs by cell ID.

## Stats

- `NeoNotebookStats` reports the total cell count and a code/markdown breakdown.

## Run all and session control

- `NeoNotebookRunAll` executes all code cells in order.
- `NeoNotebookRestart` stops the Python session and clears outputs.
- `NeoNotebookOutputToggle` switches between inline and floating output.
- `NeoNotebookRunAbove` runs code cells above the cursor.
- `NeoNotebookRunBelow` runs code cells below the cursor.
- `NeoNotebookAutoRenderToggle` toggles auto-rendering.
- `run_all` / `run_above` / `run_below` now benefit from serialized execution via the
  shared execution queue, preventing overlapping requests/output races.

## Output rendering

- Outputs are stored in a per-buffer map keyed by `cell_id`.
- Output is rendered as a virtual block below the cell with a purple border,
  attached to the cell's bottom border.

## Rich rendering (optional)

- If `rich` is available, the last expression uses Rich for rendering.
- Pandas DataFrames/Series are rendered as tables (row/col limits configurable).
- Runtime toggle via `neo_rich(True|False)`.

## Help window

- `NeoNotebookHelp` opens a floating help summary built from current keymaps.

## Floating cell editor

- `NeoNotebookCellEdit` opens the current cell in a scratch floating buffer.
- `NeoNotebookCellSave` writes the editor buffer back to the source cell.
- `NeoNotebookCellRunFromEditor` saves and executes the edited cell (code only).

## Cell labels

- Borders can include a numeric cell index when `show_cell_index = true`.

## Vertical borders

- When enabled, cell bodies render a left sign column border and a right aligned border.

## Border styling and width

- Code and markdown borders use separate highlight groups.
- Width is centered and responsive based on `cell_width_ratio`, clamped by min/max.
- `top_padding` inserts real blank lines at the top of the buffer on first open to keep the top border visible.
- `trim_cell_spacing` collapses extra blank lines between cells once per buffer.
- `cell_gap_lines` controls how many blank lines to keep between cells (default 1).
- `soft_contain` remaps `o`, `O`, and `<CR>` to keep edits within a cell.
- `strict_containment = "soft"` enforces containment on edit-entry points (InsertEnter/Enter handlers).
- `contain_line_nav` remaps `j/k` to stay within active cell editable bounds.
- `textwidth_in_cells` sets `textwidth` to the cell inner width for soft line wrapping.

## Cell list enhancements

- Cell list entries include line numbers and a short snippet from the cell body.
- Selecting a cell centers the view.

## Cell index cache

- The plugin stores a per-buffer cache of cell ranges to avoid repeated parsing.
- Buffer mutations mark the cache dirty; reads rebuild lazily only when needed.
- Cache validity is also guarded by `changedtick`.
- When edits do not touch marker lines, incremental line-delta updates are applied and
  the updated index is re-assigned to the buffer to persist mutations.
- Cache format: `list` (ordered) and `by_id` (O(1) lookup).
- Each cell has a stable `cell_id` stored as an extmark on the marker line.
- Each cell entry stores `body_len` for positioning math.
- If marker lines are touched or inserted, the index falls back to a full rebuild.

## Render scheduling

- `lua/neo_notebooks/scheduler.lua` coalesces bursty render requests per buffer.
- Text-change hooks and spinner ticks request debounced renders instead of forcing
  immediate redraws on every event.
- Scheduler requests can target specific cell IDs to redraw only affected cells,
  falling back to full renders when needed.

## Render scheduling

- `lua/neo_notebooks/scheduler.lua` coalesces bursty render requests per buffer.
- Text-change hooks and spinner ticks request debounced renders instead of forcing
  immediate redraws on every event.
- Immediate redraws are still used where UX requires direct feedback.

## Tests

- Headless tests live in `tests/run.lua`.

## .ipynb import/export

- Import reads `.ipynb` JSON and converts cells to marker format.
- Import drops a leading blank code cell when followed by markdown (common notebook artifact).
- Export writes a minimal `.ipynb` with cell sources (no outputs).
- Open creates a new buffer, sets `filetype=python`, and imports content.
- When `auto_open_ipynb` is enabled, reading a `.ipynb` auto-opens it into a scratch buffer.
- `.ipynb` buffers use `buftype=acwrite`; `:w` triggers export to the original file.

## Auto-render and keymaps

- Auto-render is gated by:
  - `filetypes` (default `{ "neo_notebook", "ipynb" }`) OR a buffer flag (`b:neo_notebooks_enabled`).
  - Optional `require_markers` to render only when markers are present.
- Keymaps are buffer-local and only set when buffers pass the gating rules.

## Automatic first cell

- On `FileType` for eligible buffers, if the buffer is empty and has no markers,
  the plugin inserts `# %% [markdown]` and moves the cursor to the empty line below.

## Future work

- Add a proper markdown renderer for headings/emphasis.
- Provide navigation and cell list UI.
- Add Lua tests for parsing and execution.
