# Changelog

This project did not previously track a changelog. The entries below are a
best-effort summary based on existing documentation and recent commits.

## Unreleased

- Added per-cell execution timing displayed at the top of inline output blocks.
- Added incremental rendering and index updates to reduce full-buffer redraws.
- Added render scheduler for debounced redraws and spinner updates.
- Added `:NeoNotebookCellIndexToggle` to toggle numeric cell index labels.
- Improved cursor clamping to cell boundaries after navigation and run-and-next.

## Earlier (high-level)

- Core notebook behaviors: cell markers, borders, inline output, and execution.
- Floating output option and markdown preview.
- `.ipynb` import/export workflow with auto-open and auto-save.
- Containment and spacing rules for cell navigation and edits.
- Stable cell IDs and output preservation on cell moves.
