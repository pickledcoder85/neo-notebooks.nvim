# TODO

This file tracks project scope and the order of work. Items can be moved as priorities change.

## Now

- No active “Now” items. Pick from **Next**.

## Next

- Output collapse/expand per cell.
- Typed output pipeline (MIME-aware):
  - Python runner returns typed outputs: `text`, `image/png`, optional `text/html`, `application/json`.
  - Output schema: list of `{ type, data, meta }` entries.
  - Neovim renderer chooses output strategy per type.
  - Terminal capability detection (kitty graphics) with fallback modes.

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
- Fix undo (`u`) keeping cursor position within current cell (avoid jump to buffer end).
- Optional fun keymap: insert a new code cell containing a mini terminal snake game.
  - Game runs inline within the cell boundaries.
  - Random apple placement.
  - Movement controls via `h/j/k/l`.
  - `<Esc>` exits game mode and restores the cell to a normal editable code cell.

## Done (recent)

- Partial cell rerendering (redraw affected cells only, not full notebook).
- Layout fixes:
  - Re-render on window enter/resize to keep borders aligned.
  - Left padding alignment fixes around insert/indent behavior.
- Dirty-range index updates:
  - Multi-cell dirty marking and in-place marker type edits.
  - Added tests for dirty-range updates and marker-type edits.
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
- Stable cell IDs across marker edits and deletions.
- Delete motions guard `d{motion}` inside cell boundaries.
- Render rebuild on line-count changes to prevent border overlap.
- Output preservation on cell move (stable).
- Manual validation checklist completed on `notebooks/test.ipynb`.
- Dropped floating UI experiment branches.
- blink.cmp auto-show suppression helper for notebook buffers.
- New-line padding strategy: pre-insert left-boundary spaces on `o`/`O`/`<CR>`, keep during insert for correct auto-indent, then trim on `InsertLeave`/save/run.
