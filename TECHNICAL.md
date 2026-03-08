# Technical Notes

This document summarizes implementation choices and the evolution of core features.

## Documentation gate

- Any merge into `main` must reconcile `README.md`, `TODO.md`, and `TECHNICAL.md` for
  behavior/config/architecture changes.
- Refactor/review sweeps must follow `CODEBASE_REVIEW.md` and keep its sweep artifacts current.
- For any refactor phase derived from sweep findings, implementation may not start until a
  detailed phase worklist exists in `CODEBASE_REVIEW.md` that includes:
  - issue-by-issue task list mapped to sweep findings,
  - exact files to touch per task,
  - specific tests to add/update/run per task,
  - acceptance criteria per task.
- The `TODO.md` "Now/Next" sections should be accurate before merge; move completed
  items into "Done (recent)" as part of the merge process.
- When running headless tests, ensure any spawned `nvim` processes are terminated
  (use `tty=true` and send `SIGINT` on failures).
- For any new feature taken from `TODO.md`:
  - Make an implementation plan.
  - Review the plan for simplification/optimization.
  - Update the plan accordingly.
  - Move to a feature branch (if not already) and implement the updated plan.
- For refactor phases:
  - follow the same plan lifecycle (`draft -> simplify/optimize -> updated plan -> implement`);
  - keep `ARCHITECTURE_FLOWCHARTS.md` updated with current/target diagrams and phase progress;
  - keep `CODEBASE_REVIEW.md` phase status and checklists in sync with implemented changes.

## Error/notify policy

- Internal modules should prefer returning `(ok/value)` or `(nil, err)` over direct `vim.notify` side effects.
- Command boundaries (entrypoint command handlers) are the preferred owner of user-facing notifications.
- Current migration status: Phase 6 complete. Output print/collapse, cell yank, split/toggle actions, markdown preview/editor actions, run-cell request failures (including run-all/subset aggregated summaries), restart/stats actions, and containment guard-warning flows are boundary-owned; debug-only notify paths remain gated by `vim.g.neo_notebooks_debug_output`.
- Never merge and delete a feature branch until manual testing has been completed
  and explicitly approved. After implementing a revised feature plan, provide a
  manual test checklist for approval before merging/deleting the branch.

## Architecture overview

- `plugin/neo_notebooks.lua`
  - Defines notebook gating/config helper functions and delegates entrypoint wiring via `lua/neo_notebooks/entrypoint/init.lua`.
- `lua/neo_notebooks/entrypoint/init.lua`
  - Bootstrap that wires command/keymap/lifecycle registration modules.
- `lua/neo_notebooks/entrypoint/commands.lua`
  - Owns `nvim_create_user_command` registrations and command-level glue flows.
- `lua/neo_notebooks/entrypoint/keymaps.lua`
  - Owns default notebook keymaps and snake lock/restore keymap transitions.
- `lua/neo_notebooks/entrypoint/lifecycle.lua`
  - Owns notebook lifecycle autocmd wiring (open/import/render/scheduler/cleanup flows).
- `lua/neo_notebooks/mutation.lua`
  - Shared mutation helper for canonical `line edit -> index sync -> render request` sequencing at migrated call sites.
  - Named modes:
    - `raw` = edit only
    - `index_only` = edit + `index.mark_dirty`
    - `index_and_render` = edit + `index.on_text_changed` + immediate `scheduler.request_render`
- `lua/neo_notebooks/formats/jupytext_percent.lua`
  - Owns Jupytext `py:percent` parsing and default Jupytext metadata generation used by format adapters.
- `lua/neo_notebooks/formats/ipynb_outputs.lua`
  - Owns conversion between nbformat output objects and NeoNotebook typed output items.
- `lua/neo_notebooks/formats/ipynb_codec.lua`
  - Owns `.ipynb` document decode/encode and import/export cell/document assembly helpers.
- `lua/neo_notebooks/formats/notebook_adapter.lua`
  - Owns buffer-facing format adapter workflows (`import/export/open`, state synchronization, output-state updates).
- `lua/neo_notebooks/ipynb.lua`
  - Compatibility shim that re-exports `lua/neo_notebooks/formats/notebook_adapter.lua`.
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
- `lua/neo_notebooks/session_state.lua`
  - Owns lightweight per-buffer kernel/session state snapshots and transition helpers.
  - Used as the Phase 7 foundation for explicit runtime state tracking.
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

## Kernel controls (Phase 7 in progress)

- Kernel/session control UX is planned as keymap-first, with command aliases retained.
- Proposed default controls under `<leader>k*`:
  - `<leader>kr`: restart kernel session
  - `<leader>ki`: interrupt active execution
  - `<leader>ks`: stop/shutdown current kernel session
  - `<leader>kp`: pause/unpause run-queue dispatch
  - `<leader>kk`: toggle persistent kernel status panel
- Command aliases now available:
  - `:NeoNotebookKernelRestart`
  - `:NeoNotebookKernelInterrupt`
  - `:NeoNotebookKernelStop`
  - `:NeoNotebookKernelPauseToggle`
  - `:NeoNotebookKernelStatus`
  - `:NeoNotebookKernelStatusToggle`
  - `:NeoNotebookKernelBadgeToggle`
- Important semantics:
  - `pause` means dispatch pause (hold dequeue/start of new requests), not OS-level process suspend.
  - `kernel_recovery_retries` (default `1`) controls bounded dispatch-time auto-recovery attempts.

## Planned kernel status visibility (Phase 7)

- Primary channel: statusline integration via lightweight API:
  - `require("neo_notebooks").kernel_status()`
- Intended use: lualine/custom statusline can render compact text like `kernel:idle`, `kernel:running`, `kernel:error`.
- Secondary channel: virtual status badge in notebook buffer (enabled by default, set `kernel_status_virtual = false` to disable).
- Optional viewport virtual padding can render top/bottom breathing room while scrolling (`viewport_virtual_padding = { top = 2, bottom = 2 }`).
- Canonical status color semantics:
  - green: `idle/ok`
  - yellow: `running`, `interrupting`, `restarting`, `paused`
  - red: `error`, `stopped`

Current Phase 7 baseline:
- `kernel_status()` is now available and returns normalized strings (`ok`, `paused`, or raw state names).
- Session state defaults to `stopped` before first run; transitions now enforce a stricter state machine contract (no direct `stopped -> running` bypass).
- Kernel status mapping/format/highlight semantics are centralized in `kernel_status.lua` so badge, panel, notify output, and statusline use one canonical source.
- Kernel control keymaps/commands and dispatch pause gating are implemented.
- Persistent kernel status panel toggle is implemented via `<leader>kk` / `:NeoNotebookKernelStatusToggle`.
- Optional virtual status badge is implemented via `kernel_status_virtual = true`.
- Bounded dispatch-time auto-recovery is implemented for dead sessions (`kernel_recovery_retries`).
- Integration coverage now includes queue pause/resume dispatch boundary and interrupt/restart recovery boundary flows.

## Output handling

- Output defaults to inline `virt_lines` under the cell.
- Floating output is still available by setting `output = "float"`.
- Floating output buffers are `nofile` and `bufhidden=wipe` and close on `q` or `<Esc>`.
- Output blocks can be collapsed/expanded per cell.
- Typed outputs are supported (text + image/png), with custom kitty graphics rendering in a dedicated image pane. When running inside tmux, the pane is created automatically and targeted via its TTY.
- While a cell is executing, a spinner is rendered on the first inline output row.
- While a cell runs, the output area shows a placeholder line.
- After execution, the inline output prepends a right-aligned timing line.
- Execution duration is measured around the request/response boundary and stored per cell ID.
- Spinner frames request immediate renders to avoid dropped updates.

## Markdown preview

- `:NeoNotebookMarkdownPreview` opens a centered floating window.
- Markdown is highlighted using Neovim's `markdown` filetype.
- Font sizes are not changed (Neovim does not support per-heading font sizes in a single buffer).
- Inline markdown cells are visually formatted in-place via virtual text overlays:
  - heading markers (`#`, `##`, ...) are rendered as styled heading text;
  - inline emphasis/code spans (`**bold**`, `*italic*`, `` `code` ``) are highlighted;
  - fenced blocks tagged `python` are tokenized via Tree-sitter highlight captures when available;
  - fenced block rendering gracefully falls back to raw markdown block highlighting if Tree-sitter support is unavailable;
  - overlays are disabled while actively editing that markdown cell in insert mode.

## Cell overlay preview

- The overlay is a scratch floating window that mirrors the current cell's lines.
- It is read-only and updates on cursor and text changes.
- The overlay is optional and can be toggled per buffer.

## Completion suppression in markdown cells

- When enabled, the plugin sets `vim.b.completion = false` inside markdown cells.
- The previous buffer-local completion setting is restored when returning to code cells.

## Filetype handling

- `.ipynb` and `.nn` buffers set `filetype=python` using `:setfiletype` to trigger
  `FileType` autocommands for LSP/indent configuration.

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

## Snake mode

- `NeoNotebookSnakeCell` inserts a new code cell and enters a mini inline snake mode.
- The game renders via virtual-text overlay inside the cell body; source lines remain blank host rows.
- Default board size is fixed at `25x10` (width x height) unless overridden in code.
- Snake auto-moves on a per-buffer timer; `h/j/k/l` updates direction and speed increases as apples are consumed.
- A per-buffer high score is tracked while the notebook buffer remains open and shown in the HUD.
- Snake visuals use dedicated highlight groups:
  `NeoNotebookSnakeHud`, `NeoNotebookSnakeBorder`, `NeoNotebookSnakeHead`, `NeoNotebookSnakeBody`, `NeoNotebookSnakeApple`, `NeoNotebookSnakeGameOver`.
- Snake mode installs a restricted keymap so only `h/j/k/l`, `<leader>` (pause/resume), and `<Esc>` are active while playing.
- `<Esc>` exits snake mode by deleting the snake cell and restoring normal notebook keymaps.
- Hitting a wall or the snake body also ends the game and deletes the snake cell.

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
- `u` is remapped in notebook buffers to run native undo then clamp cursor back into the active cell body/protected bounds.
- `textwidth_in_cells` sets `textwidth` to the cell inner width for soft line wrapping.
- New-line insertions pre-pad with left-boundary spaces during insert to preserve auto-indent,
  then trim padding on `InsertLeave` and before execution/export.

## Cell list enhancements

- Cell list entries include line numbers and a short snippet from the cell body.
- Selecting a cell centers the view.

## Cell index cache

- The plugin stores a per-buffer cache of cell ranges to avoid repeated parsing.
- Buffer mutations mark the cache dirty; reads rebuild lazily only when needed.
- Cache validity is also guarded by `changedtick`.
- When edits do not touch marker lines, incremental line-delta updates are applied and
  the updated index is re-assigned to the buffer to persist mutations.
- Marker line edits that keep valid markers update cell types in-place without a full rebuild.
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

## Tests

- Headless tests live in `tests/run.lua`.
- Jupytext compatibility fixtures live in `tests/fixtures/jupytext/` and are validated in headless tests.
- Performance fixtures live in `tests/fixtures/perf/` and are used by a dedicated stress lane.
- Fixture coverage includes:
  - upstream README/docs examples,
  - mixed marker variants (`[md]`, indented `# %%`),
  - malformed header fallback cases (missing closing `# ---`),
  - import error paths (missing file, non-modifiable target buffer).
  - manual stress fixtures for interactive execution workloads:
    - `tests/fixtures/perf/manual_exec_stress.ipynb`
    - `tests/fixtures/perf/manual_exec_soak.ipynb`
- Test lanes:
  - `tests/core_contract.lua` (required core signal; skips optional kitty backend assertions)
  - `tests/integration.lua` (broad workflow signal; skips optional kitty backend assertions)
  - `tests/optional_kitty.lua` (kitty/image backend assertions; optional in non-kitty environments)
  - `tests/performance.lua` (optional stress/perf signal over large synthetic fixtures with conservative timing budgets)
    - includes batch compute workload (`5000` calculations in batches of `100`)
    - includes high-volume output streaming workload
    - includes local fetch-style workload (`urllib` + `file://` JSON payload, 5000 rows)
    - optional real network fetch path is gated by `g:neo_notebooks_test_include_network=1`
  - integration lane includes snake lifecycle/keymap ownership transition assertions.

## .ipynb import/export

- Import reads `.ipynb` JSON, preserves notebook/cell metadata and outputs, and converts cells to marker format.
- Import drops a leading blank code cell when followed by markdown (common notebook artifact).
- Import renders existing code-cell outputs using the typed output pipeline.
- Export writes a full `.ipynb` with cell sources, metadata, execution counts, and outputs.
- Open creates a new buffer, sets `filetype=python`, and imports content.
- When `auto_open_ipynb` is enabled, reading a `.ipynb` auto-opens it into a scratch buffer.
- `.ipynb` buffers use `buftype=acwrite`; `:w` triggers export to the original file.
- After import/open setup mutations, undo baseline is reset to prevent `u` from rolling back to raw JSON view.

## Jupytext `py:percent` interop (v1)

- `import_jupytext(path, bufnr)` parses Jupytext percent-style Python files into marker cells.
- Supports cell markers: `# %%`, `# %% [markdown]`, and `# %% [md]`.
- Markdown cell bodies convert from percent-comment lines to plain markdown text.
- A lightweight YAML-comment header parser reads `metadata.jupytext` when present.
- If missing, default `metadata.jupytext` is seeded (`ipynb,py:percent` + percent text representation).
- `open_jupytext(path)` opens a new notebook-view buffer and imports the Jupytext file.
- `.ipynb` export preserves the in-memory `metadata.jupytext` block.

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
