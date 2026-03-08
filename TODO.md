# TODO

This file tracks project scope and the order of work. Items can be moved as priorities change.

## Now

- Docs/state sync:
  - Keep `TODO.md`/`TECHNICAL.md`/`ARCHITECTURE_FLOWCHARTS.md` aligned with merged work before starting each new feature.
  - Ensure `Now` only contains active, unmerged work.
- Structured codebase review sweeps (see `CODEBASE_REVIEW.md`):
  - Sweep 1: contract map (completed; module/API/state/UI artifacts documented).
  - Sweep 2: architecture assessment (event flow, coupling hotspots, simplification opportunities).
  - Sweep 3: dead code + optimization candidates (document only).
  - Sweep 4: sequenced refactor execution plan with risk/test/rollback strategy.
  - Sweep 5 (optional): test/observability gap assessment (completed; prioritized gaps documented).
  - Phase 2 (completed): test lane split (`core_contract`, `integration`, `optional_kitty`) with README lane invocations.
  - Phase 3 (completed): entrypoint decomposition (keymap/lifecycle/command wiring extracted with bootstrap module).
  - Phase 4 (completed): mutation/render contract consolidation (shared mutation helper + named modes + migrated high-traffic call sites).
  - Phase 5 (completed): format layer split (Jupytext parser + output codec + ipynb codec + notebook adapter split).
  - Phase 6 (completed): error/notify policy (boundary-owned notifications + debug-gated internal notify paths).
  - Phase 7 (completed): kernel/session state machine + recovery policy (state-owner, status API, kernel controls, persistent panel, optional virtual badge, queue-pause dispatch gating, bounded dispatch-time auto-recovery, and dead-active-request reconciliation landed).

## Next

- Priority 1: Performance/scalability hardening follow-through:
  - Profile render/index/scheduler hot paths on large notebooks.
  - Add stress tests for high output volume and long-running edit/render loops.
  - Define and enforce baseline regression thresholds (render latency, queue latency) for CI/local gates.
  - Progress update:
    - Added synthetic large fixtures (`tests/fixtures/perf`) and optional `tests/performance.lua` lane with conservative timing budgets for import/index/render/export.
    - Added execution stress coverage for batch compute, large streamed output, and fetch-style large-data read (`file://` payload), with optional real network fetch gate.
    - Streaming-depth v1: live stream preview now uses event-order merging with a global preview cap, plus carriage-return sanitization and placeholder configurability.
    - Manual soak fixture now supports non-`tqdm` progress styles (`pct`, `ratio`, `bar`) for UX testing of default streaming behavior.

- Priority 2: Reliability contracts for format interop follow-through:
  - Expand Jupytext fixture corpus with additional real-world repos.
  - Tighten round-trip invariants for metadata/outputs across NeoNotebooks and IDEs (cross-IDE coverage).
  - Progress update:
    - Added malformed `.ipynb` shape validation (top-level and `cells` field) with explicit errors.
    - Added import normalization for unknown cell types, string `source`, and malformed metadata/attachments/outputs.
    - Added core-contract tests for malformed-shape rejection and normalization/export invariants.

- Priority 3: UI/Neovim integration polish:
  - Close cursor/alignment edge cases under resize/split/tab transitions.
  - Further stabilize keymap/lifecycle behavior across buffer attach/detach flows.
  - Improve long-running execution status visibility.

- Priority 4: Architecture formalization + cleanup sweep:
  - Revisit module boundaries, dependency direction, and state ownership.
  - Remove dead code and tighten high-risk error paths.
  - Add regression tests around refactored hotspots.

## Later

- UI parking lot (non-blocking polish bugs):
  - Viewport virtual top padding can render inconsistently with large cells during certain navigation paths (notably `<C-n>` jumps when viewport lands mid-cell). Bottom padding is stable; top padding needs a more reliable viewport-anchor strategy.

## Lowest priority

- Kernel-backed execution (minimal Jupyter client with text/plain only), with optional kitty image output.

## Done (recent)

- Improved markdown rendering polish:
  - Inline markdown overlay for headings and emphasis/code spans.
  - Fenced code blocks (` ```lang ... ``` `) rendered with markdown-aware highlight groups.
  - Fence markers remain visible for editing context.
- Added optional viewport virtual padding (`viewport_virtual_padding`) so notebook cells keep top/bottom breathing room while scrolling.
- Streaming-depth polish:
  - Live preview preserves event order across streams, uses a global preview cap, and strips raw carriage returns from stream chunks.
  - Added `stream_placeholder_text` config for execution placeholder customization.
  - Added integration coverage for live preview cap + carriage-return replacement behavior.
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
