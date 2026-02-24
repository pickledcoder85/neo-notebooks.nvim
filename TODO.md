# TODO

This file tracks project scope and the order of work. Items can be moved as priorities change.

## Now

- Verify inline output behavior for `<leader>r` and `<S-CR>` after merge on real notebooks.
- Reconcile floating UI experiments vs. mainline behavior (keep experimental or drop).
- Verify output blocks render attached to cell bottom (no overlap), including after moves and reruns.
- Decide whether to preserve outputs on cell move (currently clears all outputs) now that alignment is more stable.
- Manual validation checklist (main, `notebooks/test.ipynb`):
  - Setup:
    1. `git checkout main`
    2. Open `notebooks/test.ipynb` in Neovim.
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
       - Expect: cell moves up/down; rerun cell and output attaches correctly.
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

- True dirty-range index updates (avoid full-buffer cell scans where possible).
  - Robustness-first: keep full rebuild fallback whenever partial updates are unsafe.
- Partial cell rerendering (redraw affected cells only, not full notebook).
- Stabilize cell IDs across marker edits and deletions.
- Output collapse/expand per cell.
- Add a UI action menu (Telescope-style picker).

## Later

- Full `.ipynb` metadata + outputs support.
- Kernel-backed execution (minimal Jupyter client with text/plain only), with optional kitty image output.
- Optional execution dependency awareness:
  - Detect likely upstream cell dependencies and warn on reordered runs.
  - Offer targeted "run required predecessors" before executing a moved cell.
  - Keep default behavior globally scoped for lightweight workflows.
- Optional inline image rendering via kitty protocol.
- True floating-cell UI mode (editable floats synced to hidden buffer).
- Improved markdown rendering (headings, emphasis).
- Optional markdown cell rendering polish (conceal/emphasis; Tree-sitter-based).
- Optional fun keymap: insert a new code cell containing a mini terminal snake game.
  - Game runs inline within the cell boundaries.
  - Random apple placement.
  - Movement controls via `h/j/k/l`.
  - `<Esc>` exits game mode and restores the cell to a normal editable code cell.

## Done (recent)

- Cell spacing + containment polish:
  - Cursor containment for `o`, `O`, `<CR>`, `gg`, `G`.
  - Single internal blank-line spacing and `cell_gap_lines` stabilization.
  - Insert/delete guards for marker/protected zones (`dd`, `x`, `D`, visual `d`, `<BS>`, `<Del>`, `p`).
  - Soft strict containment with cell-aware `j/k` clamped within active cell.
- `.ipynb` native workflow:
  - `ftdetect` for `*.ipynb`.
  - Auto-import on open and auto-export on save.
  - Default filetypes include `"ipynb"`.
- `.ipynb` round-trip tests (export/import) plus leading blank-code import normalization.
- Render/index synchronization improvements to prevent boundary overlap and stale placement.
- Lazy index invalidation + changedtick-aware rebuilds.
- Debounced per-buffer render scheduler for high-frequency events.
- Execution queue for serialized per-buffer runs (run cell / run-all / above / below).
- `<S-CR>` run-and-next fixes:
  - logical insert placement after last non-empty content,
  - guard against infinite empty trailing code-cell creation.
- Merged cell-index-cache into `main`.
- Stable cell IDs via extmarks.
- Cell index cache with list + by_id.
- Output placement tied to cell IDs.
- Extended headless tests.
- Shift+Enter jumps to next cell if it exists.
