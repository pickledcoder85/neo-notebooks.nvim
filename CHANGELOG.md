# Changelog

This project did not previously track a changelog. The entries below are a
best-effort summary based on existing documentation and recent commits.

## Unreleased

- Kernel/session robustness:
  - Added dead active-request reconciliation when kernel exits mid-flight.
  - Stale busy state is now cleared (`kernel:error`) and next-run recovery path is preserved.
  - Added integration coverage for forced kernel death during active execution + successful follow-up recovery.
- Streaming output depth:
  - Added incremental stream event sequencing and arrival-order live preview merging.
  - Added global live preview cap and render-pressure throttling.
  - Added configurable execution placeholder text (`stream_placeholder_text`).
  - Improved carriage-return handling for progress updates and stream sanitization.
- Streaming UX defaults:
  - Added default non-`tqdm` progress formatting policy (`bar`) for recognized `*_PROGRESS` lines.
  - Added style overrides: `bar`, `pct`, `ratio`, `raw`.
  - Added `stream_progress_bar_width` config.
  - Added integration tests for default bar-style progress rendering.
- UI/theme polish:
  - Output text now links to colorscheme-aware highlight groups (no hardcoded purple default).
  - Spinner/output defaults now better respect user theme palettes.
- Performance/scalability:
  - Added manual stress/soak fixtures (`manual_exec_stress.*`, `manual_exec_soak.*`).
  - Added execution stress workloads for batch compute, large stream output, and local fetch paths.
  - Added optional performance lane with timing budgets and synthetic large fixtures.
  - Added performance budget policy controls: `conservative|strict` profile plus optional numeric scaling (`g:neo_notebooks_perf_budget_scale`).

- Added initial Jupytext `py:percent` interoperability:
  - `:NeoNotebookImportJupytext {path}` imports Jupytext percent files into notebook cells.
  - `:NeoNotebookOpenJupytext {path}` opens a Jupytext percent file in a new notebook-view buffer.
  - Markdown percent-comment lines are converted to markdown cell text in notebook view.
  - `metadata.jupytext` is parsed (when present), seeded (when missing), and preserved on `.ipynb` export.
  - Added tests for Jupytext import parsing and metadata round-trip behavior.
  - Added compatibility fixtures sourced from official Jupytext README/docs examples.
- Full `.ipynb` metadata + outputs support (preserve metadata, execution_count, outputs; render outputs on import).
- Improved `.ipynb` MIME interop rendering:
  - Imported `text/html` now renders as readable inline text.
  - Imported `application/json` now renders as JSON text (including JSON-object payloads).
  - `text/plain` object repr fallback is suppressed when richer HTML/JSON MIME is present.
- Added per-cell output collapse/expand toggle (default: `<leader>of`).
- Added typed output support with custom kitty image rendering to a tmux image pane (auto-created when TMUX is available, or via explicit TTY).
- Added image pane size toggle (`<leader>pt`), collapse (`<leader>pc`), and statusline size indicator.
- Matplotlib backend defaults to `Agg` to prevent GUI popups during inline capture.
- `plt.show()` is intercepted to trigger inline image capture without GUI.
- Clearing output now clears execution hashes so re-running produces output.
- Improved dirty-range index updates (multi-cell dirty marking and in-place marker type edits).
- Added tests covering dirty-range updates and marker-type edits.
- Insert-mode padding is now preserved for auto-indent, then trimmed on exit/run.
- Auto-indent/LSP now loads for `.ipynb`/`.nn` via `:setfiletype python`.
- Re-render on window enter/resize to keep borders aligned to size changes.
- Added optional cursor padding debug command (`:PadDebug`).
- Added "Who this is for" guidance in `README.md`.
- Added per-cell execution timing displayed at the top of inline output blocks.
- Added incremental rendering and index updates to reduce full-buffer redraws.
- Added render scheduler for debounced redraws and spinner updates.
- Added `:NeoNotebookCellIndexToggle` to toggle numeric cell index labels.
- Improved cursor clamping to cell boundaries after navigation and run-and-next.
- Changed default run-above/run-below mappings to `<leader>rk`/`<leader>rj`.
- Added per-buffer execution queue to serialize runs within a notebook.
- Added notebook-only `scrolloff` padding to keep context below the cursor.
- `run_below` now includes the current cell.
- Re-running a cell can interrupt the active execution when code has changed.

## Earlier (high-level)

- Core notebook behaviors: cell markers, borders, inline output, and execution.
- Floating output option and markdown preview.
- `.ipynb` import/export workflow with auto-open and auto-save.
- Containment and spacing rules for cell navigation and edits.
- Stable cell IDs and output preservation on cell moves.
