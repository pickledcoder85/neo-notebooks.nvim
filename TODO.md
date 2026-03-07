# TODO

This file tracks project scope and the order of work. Items can be moved as priorities change.

## Now

- Jupytext interoperability (next major task):
  - Initial `py:percent` open/import support landed (`:NeoNotebookImportJupytext` / `:NeoNotebookOpenJupytext`).
  - Initial `metadata.jupytext` seed + `.ipynb` export round-trip landed.
  - Initial compatibility fixtures from official Jupytext README/docs landed (`tests/fixtures/jupytext`).
  - Expand fixture corpus with additional real-world repos to further reduce format drift risk.
- Structured codebase review sweeps (see `CODEBASE_REVIEW.md`):
  - Sweep 1: contract map (completed; module/API/state/UI artifacts documented).
  - Sweep 2: architecture assessment (event flow, coupling hotspots, simplification opportunities).
  - Sweep 3: dead code + optimization candidates (document only).
  - Sweep 4: sequenced refactor execution plan with risk/test/rollback strategy.
  - Sweep 5 (optional): test/observability gap assessment (completed; prioritized gaps documented).
  - Phase 2 (in progress): test lane split (`core_contract`, `integration`, `optional_kitty`).
  - Phase 3 (completed): entrypoint decomposition (keymap/lifecycle/command wiring extracted with bootstrap module).
  - Phase 4 (completed): mutation/render contract consolidation (shared mutation helper + named modes + migrated high-traffic call sites).
  - Phase 5 (in progress): format layer split (Jupytext percent parser extracted from `ipynb.lua`).

## Next

- Kernel/session robustness:
  - Clear restart/interrupt/status behavior with reliable state transitions.
  - Better failure-mode UX around stale kernel state and reconnect flows.
- Performance/scalability hardening:
  - Profiling + optimization passes for large notebooks and high output volume.
  - Stress tests for render/index/update loops on long-running sessions.
- UX polish/stability hardening:
  - Additional round-trip guarantees and regression coverage for cross-IDE workflows.
  - Focused quality pass on notebook ergonomics and edge-case behavior.
- Architecture formalization sweep:
  - Revisit module boundaries, event flow, and state ownership.
  - Simplify dependency direction and document architectural invariants.
- Refactor/hardening cleanup sweep:
  - Remove dead code and tighten error-path handling.
  - Refactor high-risk paths for robustness and add regression tests around them.

## Later

## Lowest priority

- Kernel-backed execution (minimal Jupyter client with text/plain only), with optional kitty image output.

## Done (recent)

- Improved markdown rendering polish:
  - Inline markdown overlay for headings and emphasis/code spans.
  - Fenced code blocks (` ```lang ... ``` `) rendered with markdown-aware highlight groups.
  - Fence markers remain visible for editing context.
- Tree-sitter fenced Python token coloring in markdown cells.
- Optional markdown cell rendering polish (conceal/theme controls for inline markdown overlays).
- Fix undo (`u`) keeping cursor position within current cell (avoid jump to buffer end).
- Optional fun keymap: insert a new code cell containing a mini terminal snake game.
  - Game runs inline within the cell boundaries.
  - Random apple placement.
  - Movement controls via `h/j/k/l`.
  - `<Esc>` or game over exits game mode and deletes the snake cell.
- Full `.ipynb` metadata + outputs support.
- Typed output pipeline (MIME-aware):
  - Python runner returns typed outputs: `text/plain`, `image/png`.
  - Output schema: list of `{ type, data, meta }` entries.
  - Neovim renderer chooses output strategy per type with kitty graphics fallback.
- `.ipynb` MIME interop rendering:
  - Render imported `text/html` outputs as readable text.
  - Render imported `application/json` outputs as JSON text.
  - Preserve MIME bundles on save while suppressing plain-object fallback repr when richer MIME exists.
- Tmux image pane rendering (kitty protocol):
  - Auto pane open/close toggle and size toggle (25/33/50%).
  - Page mode with next/prev paging to avoid scrollback limitations.
  - Temp-file image storage with fallback path output when pane is closed.
  - Pane resize redraw + aspect ratio preservation for images.
- Output collapse/expand per cell.
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
