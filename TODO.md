# TODO

This file tracks project scope and the order of work. Items can be moved as priorities change.

## Now

- Verify inline output behavior for `<leader>r` and `<S-CR>` after branch merge.
- Add `.ipynb` round-trip tests (export then import) and document limitations.
- Reconcile floating UI experiments vs. mainline behavior (keep experimental or drop).
- Verify output blocks render attached to cell bottom (no overlap), including after moves.
- Option B: `.ipynb` native workflow (new feature/test branch only):
  - Add `ftdetect` for `*.ipynb`.
  - Auto-import on open, auto-export on save.
  - Set default filetypes to `{ "ipynb" }` once stabilized.
- Manual validation checklist (main, `new_notebook.py`):
  - Setup:
    1. `git checkout main`
    2. Open `new_notebook.py` in Neovim.
  - Expected behaviors to test:
    1. Cell navigation
       - Press `<C-n>` and `<C-p>`.
       - Expect: jumps to the first line of the cell body in normal mode.
    2. Run a cell
       - Put cursor inside a code cell.
       - Press `<leader>r`.
       - Expect: output appears inline beneath the cell.
    3. Shift+Enter
       - In a code cell: `<S-CR>`
       - Expect: runs the cell, then jumps to next cell if it exists, otherwise creates a new code cell and enters insert mode.
       - In a markdown cell: `<S-CR>`
       - Expect: jumps to next cell if it exists, otherwise creates a new code cell and enters insert mode.
    4. Move cells
       - Put cursor in a cell and run `<M-k>` or `<M-j>`.
       - Expect: cell moves up/down and still runs/output attaches correctly.
    5. Split/Duplicate/Delete
       - Split: `<leader>xs`
       - Duplicate: `<leader>yd`
       - Delete: `<leader>dd`
       - Expect: structure updates correctly; navigation still works.
    6. Output placement after moves
       - Run a cell, then move it.
       - Run again.
       - Expect: output appears under the moved cell (not the old location).
    7. Stats
       - `<leader>ns`
       - Expect: correct counts of code vs markdown cells.

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

- Merged cell-index-cache into `main`.
- Stable cell IDs via extmarks.
- Cell index cache with list + by_id.
- Output placement tied to cell IDs.
- Extended headless tests.
- Shift+Enter jumps to next cell if it exists.
