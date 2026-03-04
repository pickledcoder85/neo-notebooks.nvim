# Changelog

This project did not previously track a changelog. The entries below are a
best-effort summary based on existing documentation and recent commits.

## Unreleased

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
