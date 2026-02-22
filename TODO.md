# TODO

This file tracks project scope and the order of work. Items can be moved as priorities change.

## Now

- Decide whether the cell-index-cache branch should be merged into `main`.
- Verify inline output behavior for `<leader>r` and `<S-CR>` after branch merge.
- Add `.ipynb` round-trip tests (export then import) and document limitations.
- Reconcile floating UI experiments vs. mainline behavior (keep experimental or drop).

## Next

- Incremental index updates (avoid full rebuilds on every edit).
- Stabilize cell IDs across marker edits and deletions.
- Execution queue (serialize outputs for run-all/above/below).
- Output collapse/expand per cell.
- Add a UI action menu (Telescope-style picker).

## Later

- Full `.ipynb` metadata + outputs support.
- Optional inline image rendering via kitty protocol.
- True floating-cell UI mode (editable floats synced to hidden buffer).
- Improved markdown rendering (headings, emphasis).

## Done (recent)

- Stable cell IDs via extmarks.
- Cell index cache with list + by_id.
- Output placement tied to cell IDs.
- Extended headless tests.
- Shift+Enter jumps to next cell if it exists.
