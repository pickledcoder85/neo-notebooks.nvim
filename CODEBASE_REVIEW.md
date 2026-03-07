# Codebase Review Sweeps

This document defines the structured review process used before major refactors.

## Scope

Every sweep must cover:
- Core architecture and module contracts.
- UI/render behavior (borders, overlays, markdown/output rendering, snake mode UI where relevant).
- Neovim integration (autocmd lifecycle, keymap ownership, extmarks, buffer/window/filetype assumptions).

## Sweep Order

1. Contract map sweep
- Goal: define explicit module boundaries, APIs, and invariants.
- Output:
  - Module inventory with owner/responsibility.
  - Public API surface and internal-only functions.
  - Contract table (inputs/outputs/state ownership/error handling).
  - Known ambiguity list.

2. Architecture assessment sweep
- Goal: identify coupling, event-flow complexity, and structural inefficiencies.
- Output:
  - Event-flow map (commands/autocmds -> modules -> side effects).
  - Coupling hotspots and dependency-direction violations.
  - High-level simplification opportunities with risk notes.

3. Dead code and optimization sweep
- Goal: find removable code and low-risk performance wins.
- Output:
  - Dead/redundant code candidates.
  - Duplicate logic candidates.
  - Micro-optimization candidates with expected impact and risk.

4. Refactor execution plan sweep
- Goal: convert findings into a sequenced implementation plan.
- Output:
  - Ordered refactor backlog (small -> large).
  - Required tests/instrumentation per item.
  - Rollback strategy for high-risk changes.
  - Merge sequencing constraints.

5. Test/observability gap sweep (optional but recommended)
- Goal: close high-risk blind spots before large refactors.
- Output:
  - Contract-level test gaps.
  - Runtime assertions/logging hooks to add.
  - Priority matrix for reliability coverage.

## Required Artifacts Per Sweep

For each sweep, create/update a section under this document with:
- `Date`
- `Sweep owner`
- `Files reviewed`
- `Findings`
- `Risks`
- `Action items`
- `Status` (`open`, `in_progress`, `closed`)

## Refactor Phase Worklist Template (Required Before Implementation)

For each refactor phase, add a dedicated section using this template before any code changes:

- `Phase`
- `Status` (`open`, `in_progress`, `blocked`, `closed`)
- `Related sweep findings` (IDs/bullets from sweeps)
- `Detailed task list` (issue-by-issue)
- `Exact files to touch` (per task)
- `Tests`
  - tests to add/update
  - tests to run (core/integration/optional)
- `Acceptance criteria` (objective pass conditions)
- `Manual validation checklist` (if behavior can be user-visible)
- `Rollback plan` (how to revert safely)

## Documentation Gate Rules For Sweeps

Before merging sweep outputs into `main`:
- Update this file with concrete findings (not placeholders).
- Reconcile `TODO.md` (`Now/Next`) to reflect current sweep state.
- Update `TECHNICAL.md` when architectural contracts or module roles are clarified.
- If behavior or workflows are user-visible, also update `README.md`.

After each sweep implementation branch:
- Provide a short manual validation checklist when behavior changed.
- Do not merge/delete branch until explicit approval is given.

## Sweep 1 - Contract Map

- Date: 2026-03-07
- Sweep owner: Codex (GPT-5)
- Status: open

### Files reviewed

- `plugin/neo_notebooks.lua`
- `lua/neo_notebooks/init.lua`
- `lua/neo_notebooks/index.lua`
- `lua/neo_notebooks/render.lua`
- `lua/neo_notebooks/actions.lua`
- `lua/neo_notebooks/output.lua`
- `lua/neo_notebooks/scheduler.lua`
- `lua/neo_notebooks/exec.lua`
- `lua/neo_notebooks/ipynb.lua`
- `lua/neo_notebooks/snake.lua`
- `tests/run.lua`

### Findings

1. Monolithic integration surface in `plugin/neo_notebooks.lua`:
   command wiring, lifecycle, policy, and UI hooks are tightly co-located.
2. Autocmd contract is broad and overlapping:
   event-order assumptions are implicit and undocumented.
3. Buffer state is schema-less across many `vim.b[...]` keys:
   no single state accessor/contract table exists.
4. `ipynb.lua` now mixes multiple responsibilities:
   `.ipynb` I/O, Jupytext parsing, metadata policy, and open-buffer behavior.
5. Render/index/action invariants are implicit:
   authority of dirty vs rebuilt index is not formally documented.
6. Scheduler/render guarantees are under-specified:
   debounce/immediate/partial-render contract is not centralized.
7. Error handling policy is inconsistent:
   mixed return-error, notify, and silent `pcall` paths.
8. UI behavior contracts are distributed:
   markdown/output/overlay/snake expectations are not consolidated.
9. Neovim integration contracts need lifecycle formalization:
   ownership of keymaps/autocmds/extmarks by mode and buffer type is implicit.
10. Test topology has a known blocker and limited stratification:
    full suite currently stops at known kitty-path failure; tiers are not explicit.
11. Export semantics are in-memory by design:
    cross-instance expectations are currently undocumented.
12. Jupytext fixture coverage improved compatibility confidence:
    corpus should still expand for edge variants.

### Risks

- Higher regression risk during refactors due to implicit contracts.
- Harder debugging for lifecycle issues from mixed ownership and error policies.
- Performance regressions are harder to localize without explicit scheduler/render contracts.
- UX drift risk because UI expectations are not captured in one contract matrix.

### Action items (documentation-first)

1. Create a module contract table (owner, inputs/outputs, state touched, side effects).
2. Add an event-flow map (autocmd/command -> module call chain -> state mutations).
3. Define canonical buffer-state schema and key ownership rules.
4. Define error-handling policy tiers (return, notify, assert/pcall) per layer.
5. Add a UI contract matrix covering render/overlay/output/markdown/snake.
6. Split tests into contract tiers and isolate known-optional failures.

## Sweep 2 - Architecture Assessment

- Date: 2026-03-07
- Sweep owner: Codex (GPT-5)
- Status: open

### Files reviewed

- `plugin/neo_notebooks.lua`
- `lua/neo_notebooks/actions.lua`
- `lua/neo_notebooks/containment.lua`
- `lua/neo_notebooks/policy.lua`
- `lua/neo_notebooks/index.lua`
- `lua/neo_notebooks/render.lua`
- `lua/neo_notebooks/output.lua`
- `lua/neo_notebooks/scheduler.lua`
- `lua/neo_notebooks/ipynb.lua`
- `lua/neo_notebooks/overlay.lua`
- `lua/neo_notebooks/snake.lua`
- `tests/run.lua`

### Findings

1. `plugin/neo_notebooks.lua` remains a high-coupling orchestration module:
   commands, autocmds, keymaps, lifecycle policy, and feature wiring are concentrated.
2. Autocmd overlap introduces ordering fragility and potential redundant work:
   multiple event groups trigger shared flows (`render_if_enabled`, keymaps, completion/textwidth updates).
3. Render/output/scheduler/index paths are tightly interlocked:
   performance-sensitive but difficult to reason about without explicit sequencing contracts.
4. Format layer has mixed responsibilities:
   `ipynb.lua` handles serialization, Jupytext parsing, metadata policy, and buffer-open behavior.
5. Policy boundaries are blurred across containment/policy/actions:
   edit/nav authority precedence is implicit.
6. Keymap lifecycle/ownership is non-trivial:
   default maps, mode maps, and locked maps are managed centrally without formal ownership matrix.
7. UI behavior contracts are distributed across modules:
   no single state matrix for markdown/output/overlay/snake rendering by mode/event.
8. Neovim integration contracts are under-documented:
   extmark/autocmd/buffer-type invariants are not centralized.
9. Dynamic requires in hot paths obscure dependency direction:
   useful for cycle avoidance but reduces architectural clarity.
10. Test suite is broad but not tiered:
    known optional-path failure (kitty) reduces confidence signal for core-only changes.

### Risks

- Refactor changes may cascade across lifecycle/render paths due to high coupling.
- Event-order regressions are likely if autocmd/keymap wiring changes without a flow model.
- Performance tuning may introduce correctness regressions absent explicit scheduler/index contracts.
- UX regressions can slip through because UI contracts are not centralized.

### Action items (documentation-first)

1. Create an explicit event-flow diagram:
   user command/autocmd -> module chain -> state mutations -> render side effects.
2. Define module layering rules:
   orchestration layer, domain/action layer, state/index layer, rendering layer, format layer.
3. Extract/define ownership matrix:
   who owns keymaps/autocmds/extmarks for each buffer mode/state.
4. Define cross-module invariants for render/index/scheduler interactions.
5. Split tests into tiers:
   `core-contract`, `integration`, `optional-backend`.
6. Identify first low-risk decoupling targets (no behavior change):
   command registration extraction and lifecycle hooks extraction from plugin entrypoint.

## Sweep 3 - Dead Code and Optimization Candidates

- Date: 2026-03-07
- Sweep owner: Codex (GPT-5)
- Status: open

### Files reviewed

- `plugin/neo_notebooks.lua`
- `lua/neo_notebooks/actions.lua`
- `lua/neo_notebooks/exec.lua`
- `lua/neo_notebooks/output.lua`
- `lua/neo_notebooks/ipynb.lua`
- `lua/neo_notebooks/render.lua`
- `lua/neo_notebooks/scheduler.lua`
- `lua/neo_notebooks/cells.lua`
- `lua/neo_notebooks/snake.lua`
- `tests/run.lua`

### Findings

1. Debug-only commands appear in main plugin command surface:
   `PadDebug` and `NeoNotebookAnsiSample` are likely dev diagnostics.
2. Repeated dynamic requires in hot paths:
   frequent `require("neo_notebooks.index")` calls across actions/output/exec paths reduce clarity.
3. Dirty-marking is highly scattered:
   `index.mark_dirty` is invoked manually in many mutation locations.
4. Render triggers are fan-out heavy:
   many direct `render_if_enabled` calls may lead to redundant render requests.
5. `ipynb.lua` has grown into a mixed-concern module:
   codec + parser + metadata policy + buffer-open behaviors are co-located.
6. Notification policy is noisy and inconsistent at info-level:
   potential UX and debugging signal-to-noise issue.
7. Test execution lacks tiered entrypoints:
   known optional-backend failures reduce confidence signal for core-only changes.
8. Buffer setup logic is duplicated across import/open flows:
   repeated setup sequences increase drift risk.
9. Spinner/output/scheduler coordination likely has micro-optimization headroom:
   immediate vs debounced rerender rules are not explicit.
10. No obvious fully-dead module identified:
    current candidates are mostly cleanup/duplication reduction, not hard deletions.

### Risks

- Cleanup/refactor without contract extraction may alter behavior unintentionally.
- Performance changes in render/output paths can regress UX if scheduler semantics are not codified first.
- Removing debug surfaces without replacement can reduce troubleshooting capability.

### Action items (documentation-first)

1. Tag and classify debug/dev-only commands and globals; decide production policy.
2. Define a canonical “mutation API” that guarantees dirty-mark + render scheduling semantics.
3. Define render trigger policy:
   when to call immediate render vs scheduler request.
4. Propose module split plan for `ipynb.lua` without behavior changes.
5. Define notification-level policy and optional verbosity flag.
6. Split tests into explicit tiers and independent entrypoints.
7. List low-risk dedup targets for first cleanup wave (setup helpers, shared import/open scaffolding).

## Sweep 4 - Refactor Execution Plan

- Date: 2026-03-07
- Sweep owner: Codex (GPT-5)
- Status: open

### Objectives

- Reduce coupling and lifecycle fragility without changing user-visible behavior.
- Formalize contracts before structural refactors.
- Improve confidence/rollback safety via phased delivery.

### Sequenced plan

1. Documentation and contract baseline (no behavior changes)
- Deliverables:
  - Module contract table (ownership, inputs/outputs, side effects, state touched).
  - Event-flow map (command/autocmd -> call chain -> state mutations -> render side effects).
  - Buffer-state schema (`vim.b` key registry + ownership rules).
  - UI contract matrix (markdown/output/overlay/snake by mode and event).
- Tests:
  - No new behavior tests required; ensure existing core tests still pass.
- Rollback:
  - Revert docs-only commits.

2. Test topology split and confidence lanes
- Deliverables:
  - Split tests into `core-contract`, `integration`, and `optional-backend` entrypoints.
  - Mark known optional backend paths so core lane remains green.
- Tests:
  - Core lane mandatory before every merge.
  - Integration lane for feature branches touching lifecycle/render/index.
- Rollback:
  - Revert test harness split without touching runtime modules.

3. Plugin entrypoint decomposition (low-risk extraction)
- Deliverables:
  - Extract command registration from `plugin/neo_notebooks.lua` into dedicated module.
  - Extract lifecycle/autocmd registration into dedicated module.
  - Keep public commands/keymaps unchanged.
- Tests:
  - Core + integration lanes.
  - Manual smoke: open `.nn`, open/import/export `.ipynb`, import/open Jupytext, run cell, render behavior.
- Rollback:
  - Keep extraction in isolated commits per subsystem; revert specific extraction commit(s).

4. Mutation/render contract consolidation
- Deliverables:
  - Introduce shared mutation helper(s) that enforce:
    - dirty-mark semantics,
    - render scheduling semantics,
    - optional immediate render policy.
  - Replace duplicated setup/mutation boilerplate in high-traffic paths.
- Tests:
  - Add focused regression tests for index/layout consistency after edits/moves/imports.
  - Validate no change in key UX workflows.
- Rollback:
  - Feature-flag or commit-sliced rollout by callsite group.

5. Format layer decomposition (`ipynb.lua`)
- Deliverables:
  - Split codec/parsing/state-adapter responsibilities:
    - ipynb codec,
    - jupytext percent parser,
    - buffer integration adapter.
  - Preserve existing command/API behavior.
- Tests:
  - Existing ipynb + jupytext tests must pass unchanged.
  - Add fixture-based round-trip assertions for metadata shape.
- Rollback:
  - Land split as additive + adapter first; defer deleting old internals until parity proven.

6. Error/notify policy normalization
- Deliverables:
  - Define and apply policy by layer:
    - return errors for library modules,
    - user notifications at command boundaries,
    - debug logs behind explicit flag.
  - Classify debug-only commands (`PadDebug`, `NeoNotebookAnsiSample`) as dev-surface or remove from default.
- Tests:
  - Regression tests for command error paths and non-modifiable-buffer behavior.
- Rollback:
  - Revert policy commits independently from architecture changes.

### Priority/risk matrix

- Low risk / high value:
  - docs baseline, test split, duplicated setup extraction.
- Medium risk / high value:
  - plugin entrypoint decomposition, mutation/render helper adoption.
- Higher risk:
  - format-layer split, error-policy normalization across many call sites.

### Merge sequencing constraints

- Do not start structural module moves until contract docs and test tiers are in place.
- Keep each phase in a dedicated feature branch.
- Require manual checklist approval for phases that touch lifecycle/render/keymap behavior.

### Immediate next branch

- `feature/refactor-sweep-phase-1-contract-baseline`
- Scope: docs/contracts + test-lane split plan scaffold only; no runtime behavior changes.

## Sweep 5 - Test and Observability Gap Assessment (Optional)

- Date: 2026-03-07
- Sweep owner: Codex (GPT-5)
- Status: open

### Files reviewed

- `tests/run.lua`
- `plugin/neo_notebooks.lua`
- `lua/neo_notebooks/scheduler.lua`
- `lua/neo_notebooks/render.lua`
- `lua/neo_notebooks/output.lua`
- `lua/neo_notebooks/ipynb.lua`
- `lua/neo_notebooks/exec.lua`
- `lua/neo_notebooks/snake.lua`

### Findings

1. Core test confidence is partially masked by optional backend failures:
   known kitty-path issues can stop full-suite runs.
2. No explicit test lanes:
   `core-contract`, `integration`, and `optional-backend` are not split.
3. Lifecycle/autocmd contracts are not directly asserted:
   many high-risk event-order behaviors are only indirectly covered.
4. Keymap ownership transitions are under-tested:
   default maps vs locked snake-mode maps vs restoration paths need dedicated checks.
5. Scheduler/render coalescing behavior lacks stress-contract tests.
6. Buffer-state schema invariants are not explicitly validated in tests.
7. Error-path observability is inconsistent:
   mixed return/notify/pcall patterns reduce deterministic failure assertions.
8. Debug observability exists but is ad hoc:
   useful toggles exist but are not standardized into a coherent tracing policy.
9. Negative fixture coverage for malformed `.ipynb`/Jupytext inputs is limited.
10. No explicit contract-to-test trace matrix for UI behaviors.

### Risks

- Regressions may be hidden by optional-path failures in monolithic test runs.
- Refactors can break lifecycle/keymap behavior without early signal.
- Failure-path bugs may be harder to diagnose due to inconsistent observability.

### Action items (documentation-first)

1. Split tests into three entrypoints:
   `core`, `integration`, `optional_kitty`.
2. Add lifecycle/autocmd contract tests for high-risk event chains.
3. Add keymap ownership transition tests (default -> locked -> restored).
4. Add scheduler burst/coalescing contract tests.
5. Define and test buffer-state schema invariants.
6. Add malformed input fixtures for `.ipynb` and Jupytext parsers.
7. Add a contract-to-test traceability table in docs.

## Phase Worklist - Phase 1: Contract Baseline (Docs Only)

- Phase: 1 - Contract baseline
- Status: closed
- Related sweep findings:
  - Sweep 1: findings 1-12
  - Sweep 2: findings 1-10
  - Sweep 5: findings 2, 3, 4, 6, 10

### Detailed task list

1. Build module contract inventory table
- Map each major module to responsibility, inputs/outputs, side effects, state ownership, and error surface.
- Include UI modules and Neovim integration modules.

2. Build event-flow map
- Document key command and autocmd paths:
  - cell run/run-and-next,
  - open/import/export (`.ipynb`, Jupytext),
  - render/update loops,
  - snake mode lifecycle.
- Include event ordering assumptions and call-chain boundaries.

3. Define canonical buffer-state schema
- Enumerate owned `vim.b[...]` keys and owners.
- Define read/write boundaries and allowed value shapes.

4. Create UI contract matrix
- Document expected behavior by mode/event for:
  - markdown overlay rendering,
  - output block rendering/collapse,
  - overlay preview,
  - snake game overlays and key lock behavior.

5. Create contract-to-test trace table (docs-only draft)
- Map current contracts to existing tests and mark known gaps.
- Call out which items are deferred to Phase 2 test-lane split.

6. Update plan/status docs
- Sync `TODO.md` and `ARCHITECTURE_FLOWCHARTS.md` phase status notes.
- Ensure `TECHNICAL.md` references remain accurate.

### Exact files to touch

- `CODEBASE_REVIEW.md` (primary artifact)
- `ARCHITECTURE_FLOWCHARTS.md` (phase progress and diagram notes if needed)
- `TECHNICAL.md` (contract references and clarified architecture notes)
- `TODO.md` (phase status consistency only)

### Tests

- Tests to add/update: none (docs-only phase)
- Tests to run:
  - `nvim --headless -u NONE -c "set shadafile=NONE" -c "luafile /tmp/neo_jupytext_check.lua" -c qa` (sanity)
  - full suite optional for signal: `nvim --headless -u NONE -c "set shadafile=NONE" -c "luafile tests/run.lua" -c qa`
    - known optional-path caveat: kitty-related failure may appear

### Acceptance criteria

- Module contract inventory exists and covers core + UI + Neovim lifecycle surfaces.
- Event-flow map exists for the highest-risk paths listed above.
- Buffer-state schema table exists with ownership + value-shape notes.
- UI contract matrix exists for markdown/output/overlay/snake.
- Contract-to-test trace table exists with explicit gaps.
- Documentation-gate references are consistent across touched docs.

### Manual validation checklist

- Verify all referenced module/file names and command names match repository reality.
- Confirm each contract item has a clear owner and no placeholder/TODO wording.
- Confirm no runtime code changed in this phase.

### Rollback plan

- Revert Phase 1 docs commits only:
  - `git revert <phase1-doc-commit>` (safe; no runtime behavior impact).

### Phase 1 Execution Artifacts

#### A) Module Contract Inventory (Current State)

| Module(s) | Responsibility | Primary Inputs | Primary Outputs | State Ownership / Writes | Side Effects | Error Surface |
|---|---|---|---|---|---|---|
| `plugin/neo_notebooks.lua` | Command, keymap, and autocmd orchestration | user commands, cursor/events, config | module dispatch + render scheduling | writes many `vim.b` flags (`enabled`, lifecycle flags, key lock flags) | sets keymaps/autocmds, mutates buffers, notifies user | mostly `vim.notify` and guarded calls |
| `lua/neo_notebooks/init.lua` | config defaults + setup | user setup opts | merged runtime config | writes `M.config`, some `vim.g` statusline flags | statusline hook registration | minimal (no user-facing notify) |
| `lua/neo_notebooks/actions.lua` | notebook edit/navigation operations | bufnr, cursor line, motions | buffer/index mutations + optional output control | writes pending indent buffer key; triggers index dirty | buffer edits, cursor moves, notifications | mixed notify + policy redirect + implicit failures |
| `lua/neo_notebooks/containment.lua`, `policy.lua` | line/cell legality and edit policy | bufnr, line/col, op context | decisions (`allow/redirect/block`) | read-mostly | none (pure-ish decision helpers) | returns structured decisions |
| `lua/neo_notebooks/cells.lua` | marker-level cell parsing/creation | buffer lines, requested cell type | cell lists/current cell, inserted markers | triggers index dirty after inserts/toggles | buffer line edits | minimal explicit errors |
| `lua/neo_notebooks/index.lua` | canonical per-buffer cell index + extmark IDs | buffer lines + on_lines deltas | `list` + `by_id` + dirty/range hints | owns `vim.b.neo_notebooks_index`, attach state | extmark create/delete, index attach hooks | mostly silent recovery via rebuild |
| `lua/neo_notebooks/render.lua` | visual cell rendering + markdown overlays | cells/index/output/layout context | extmark/virt line rendering | owns tail-pad buffer var | sets/removes extmarks, may adjust trailing lines | guarded tree-sitter fallback paths |
| `lua/neo_notebooks/output.lua`, `spinner.lua` | output storage/timing/collapse + spinner state | execution payloads, cell IDs | output store updates + render requests | owns output store/timing vars + spinner runtime | render scheduling, optional image pane interactions | mixed debug notify + guarded conversions |
| `lua/neo_notebooks/scheduler.lua` | render coalescing/debounce | request options (`immediate`, cell IDs) | deferred render invocation | in-memory per-buffer schedule table | timer callbacks + render calls | mostly internal guarded flow |
| `lua/neo_notebooks/exec.lua`, `session.lua` | python session/job queue + run dispatch | code cells, run opts, restart | payloads to output/render path | owns exec hash state per buffer, in-memory sessions | starts jobs, sends/receives IPC, signals interrupts | mixed return + notify + pcall |
| `lua/neo_notebooks/ipynb.lua` | `.ipynb` and Jupytext import/export adaptation | file path + buffer | marker-buffer content + state metadata + exported JSON | owns `neo_notebooks_ipynb_state`, jupytext buffer flag | file IO, buffer rewrite, output hydration | returns `(ok, err)` in many paths |
| `lua/neo_notebooks/overlay.lua` | read-only current-cell floating mirror | active cell + cursor movement | floating overlay updates | owns overlay state in `vim.b` | creates/closes floating windows | mostly guarded with `pcall` |
| `lua/neo_notebooks/markdown.lua` | markdown preview window | current markdown cell | preview window | none durable | creates float buffer/window | warn/info notify paths |
| `lua/neo_notebooks/editor.lua` | floating cell editor | active cell, edit buffer | saved cell body + optional run | owns editor state in edit buffer | creates/saves/closes floating editor | explicit error/warn notifications |
| `lua/neo_notebooks/snake.lua` | inline snake game mode | code cell id + key directions | overlay updates + cell delete on exit | in-memory game state per buffer | timers, extmarks, buffer edits | returns `(ok, err)` + guarded callbacks |
| `lua/neo_notebooks/image_pane.lua`, `kitty.lua` | image rendering transport/pane control | image payloads + tty/tmux context | pane/kitty rendering commands | in-memory pane state + temp files | tmux shell calls, terminal control sequences | debug notifies + fallback behavior |
| `lua/neo_notebooks/navigation.lua`, `help.lua`, `stats.lua` | utility UI/navigation surfaces | cursor, maps, cell list | movement/help/stats UI | none major | notifications + floating help | straightforward notify/warn |

#### B) Event-Flow Map (High-Risk Paths)

1. Run current cell (`NeoNotebookCellRun`)

```text
command -> plugin:run_cell_with_output
        -> exec.run_cell / enqueue
        -> output.show_* / payload conversion
        -> scheduler/request or render
        -> render cell/output extmarks
```

2. Run and next (`<S-CR>`)

```text
keymap -> actions.consume_pending_virtual_indent
      -> plugin run flow + optional insert new code cell
      -> index dirty/rebuild as needed
      -> render + cursor clamp
```

3. `.ipynb` open/import/export lifecycle

```text
BufReadPost *.ipynb -> plugin autocommand
                   -> ipynb.import_ipynb
                   -> index attach + keymaps + render

BufWriteCmd *.ipynb -> ipynb.export_ipynb
                   -> file write + modified=false
```

4. Jupytext import/open + export

```text
NeoNotebookImportJupytext / OpenJupytext
  -> ipynb.import_jupytext/open_jupytext
  -> state seed (metadata.jupytext) + index rebuild
  -> standard setup + render
  -> export via NeoNotebookExportIpynb uses buffer in-memory state
```

5. Snake mode lifecycle

```text
NeoNotebookSnakeCell
  -> insert code cell + snake.start
  -> lock keymaps (h/j/k/l/<leader>/<Esc>)
  -> timer-driven moves + overlay render
  -> stop on <Esc>/collision -> delete cell -> restore keymaps
```

#### C) Canonical Buffer-State Schema (Current)

| Buffer key (`vim.b[...]`) | Owner | Shape | Write paths (authoritative) | Notes |
|---|---|---|---|---|
| `neo_notebooks_enabled` | plugin / format openers | `boolean` | plugin open/import/autocmd + ipynb open helpers | buffer eligibility gate |
| `neo_notebooks_is_ipynb` | plugin | `boolean` | `BufReadPost *.ipynb` open flow | drives write/export semantics |
| `neo_notebooks_is_jupytext` | ipynb module | `boolean` | `ipynb.import_jupytext` | informs export metadata policy |
| `neo_notebooks_skip_initial` | plugin | `boolean` | ipynb open/import lifecycle | prevents unwanted initial cell insertion |
| `neo_notebooks_ipynb_opened` | plugin | `boolean` | BufReadPost guard | prevents duplicate open-import |
| `neo_notebooks_opened` | plugin | `boolean` | startup path | one-time setup guard |
| `neo_notebooks_index` | index module | `table` (`list`, `by_id`, metadata) | `index.rebuild/on_lines/set_state` | canonical cell geometry cache |
| `neo_notebooks_index_attached` | index module | `boolean` | `index.attach` | tracks on_lines attach lifecycle |
| `neo_notebooks_tail_pad` | render module | `integer` | render tail-pad helpers | logical cell range adjustment |
| `neo_notebooks_pending_virtual_indent` | actions module | `table<string,int>` | actions enter/open helpers | temporary indent staging |
| `neo_notebooks_output_store` | output module | `table` keyed by cell id | output store setters | inline output source of truth |
| `neo_notebooks_output_timing` | output module | `table` keyed by cell id | output timing setters | duration display |
| `neo_notebooks_ipynb_state` | ipynb module | `table` (`metadata/cells/order/...`) | ipynb import/export/update | format round-trip state |
| `neo_notebooks_exec_hashes` | exec/session | `table` keyed by cell id | exec hash store + session restart | rerun skip/interrupt policy |
| `neo_notebooks_overlay` | overlay module | `table` (buf/win/cell_id/line) | overlay state helpers | current-cell preview state |
| `neo_notebooks_editor` | editor module (editor buffer) | `table` | editor open/save/run | only valid in editor scratch buffer |
| `neo_notebooks_snake_locked_keys` | plugin snake wiring | `string[]` | `set_snake_keymaps/clear` | locked map lifecycle |
| completion helper keys (`neo_notebooks_completion_*`, `neo_notebooks_prev_*`) | plugin completion guard | mixed | `update_completion` | markdown completion suppression |
| `neo_notebooks_prev_textwidth` | plugin textwidth guard | `integer` | `update_textwidth` | restore-on-exit semantics |

#### D) UI Contract Matrix (Current Behavior)

| UI surface | Trigger | Expected behavior | Authoritative modules | Test coverage state |
|---|---|---|---|---|
| Cell borders + labels | render cycle / cursor movement | borders and type labels align to computed cell layout | `render.lua`, `index.lua` | covered in broad integration tests; no dedicated geometry stress lane |
| Markdown inline overlay | markdown cell not actively edited | headings/emphasis/code spans rendered via overlay | `render.lua` markdown helpers | covered (`markdown heading/emphasis/fence` tests in `tests/run.lua`) |
| Fenced markdown python coloring | markdown fence with `python` | fence markers visible; inner python captures when available | `render.lua` tree-sitter path | covered (fence visibility/tokenization tests) |
| Output blocks | cell execution/output update | inline block render, optional collapse, timing row, spinner | `output.lua`, `spinner.lua`, `render.lua` | covered for core payloads; stress/coalescing gaps remain |
| Overlay preview window | toggle + cursor move | read-only float mirrors active cell | `overlay.lua`, plugin toggle/autocmd | behavior present; limited dedicated assertions |
| Snake mode overlay | `NeoNotebookSnakeCell` | locked keys, auto-move, overlay board, delete on exit/game over | `snake.lua`, plugin key-lock handling | covered for start/move/stop/game-over; lifecycle edge cases still mostly manual |
| `.ipynb` open/save UX | BufReadPost/BufWriteCmd | import to marker view and export back on `:w` | plugin autocmds + `ipynb.lua` | covered in import/export round-trip tests |
| Jupytext import/open | command invoke | parse `py:percent`, seed/preserve metadata | plugin commands + `ipynb.lua` | covered with synthetic + fixture tests |

#### E) Contract-to-Test Trace (Draft)

| Contract item | Existing automated coverage | Gaps / follow-up |
|---|---|---|
| Stable cell index and ID continuity | multiple `index` tests in `tests/run.lua` | add stress lane for burst edits + resize/autocmd timing |
| Marker-based cell parsing and type toggles | `cells` + marker edit tests | add malformed marker fuzz cases |
| `.ipynb` metadata/output round-trip | dedicated import/export tests | add malformed JSON/error-path fixtures |
| Jupytext `py:percent` compatibility | dedicated + fixture tests (`tests/fixtures/jupytext`) | expand real-world fixture corpus and edge headers |
| Markdown overlay rendering contract | heading/emphasis/fence tests | add insert-mode transition/disable-reenable assertions |
| Snake lifecycle contract | start/move/stop/collision tests | add keymap lock/restore dedicated test cases |
| Scheduler/render coalescing | indirect only | create explicit burst/coalescing contract tests (Phase 2) |
| Autocmd lifecycle correctness | mostly indirect | add focused lifecycle tests (BufReadPost/BufWriteCmd/FileType ordering) |
| Buffer-state schema invariants | none explicit | add schema invariant checks per key owner (Phase 2) |

#### F) Phase 1 Acceptance Check (Result)

- Module contract inventory: complete.
- Event-flow map: complete for highest-risk paths.
- Buffer-state schema table: complete.
- UI contract matrix: complete.
- Contract-to-test trace draft: complete with explicit gaps.
- Runtime behavior changes: none introduced in this phase.

## Phase Worklist - Phase 2: Test Topology Split and Confidence Lanes

- Phase: 2 - test lane split
- Status: in_progress
- Related sweep findings:
  - Sweep 1: finding 10
  - Sweep 2: finding 10
  - Sweep 5: findings 1, 2, 3, 4, 5, 6

### Detailed task list

1. Create explicit test entrypoints
- Introduce separate test runners:
  - `tests/core_contract.lua`
  - `tests/integration.lua`
  - `tests/optional_kitty.lua`
- Keep `tests/run.lua` as compatibility wrapper or dispatcher (non-breaking developer UX).

2. Extract shared test harness utilities
- Move reusable assertions/helpers (`ok`, `eq`, `with_buf`, etc.) into a shared helper module/file.
- Ensure all lanes import shared helpers, not duplicate logic.

3. Assign existing tests into lanes
- `core_contract`:
  - index/cells/policy/containment core contracts,
  - ipynb/jupytext parsing+round-trip contracts not requiring kitty.
- `integration`:
  - workflow-level command/lifecycle behavior,
  - render/scheduler interactions, snake lifecycle.
- `optional_kitty`:
  - kitty/image-pane/backend-specific checks.

4. Add lane invocation docs and scripts
- Document how to run each lane and expected failure semantics.
- Ensure gate language references core lane as required.

5. Add/adjust tests for lifecycle and keymap ownership gaps (initial minimum)
- Add focused tests for:
  - keymap lock/restore transitions in snake mode,
  - key lifecycle events around notebook open/import where practical in headless.

6. Validate and stabilize
- Confirm `core_contract` runs clean independent of kitty backend.
- Confirm optional lane is isolated and no longer blocks core signal.

### Exact files to touch

- `tests/run.lua` (dispatcher/backward compatibility)
- `tests/core_contract.lua` (new)
- `tests/integration.lua` (new)
- `tests/optional_kitty.lua` (new)
- `TODO.md` (phase status sync)
- `TECHNICAL.md` (test lane documentation updates)
- `README.md` (optional test command docs if user-facing)
- `ARCHITECTURE_FLOWCHARTS.md` (phase progress update)

### Tests

- Tests to add/update:
  - lane split harness and migrated test groups,
  - minimal new tests for keymap/lifecycle gaps from Sweep 5.
- Tests to run:
  - `nvim --headless -u NONE -c "set shadafile=NONE" -c "luafile tests/core_contract.lua" -c qa`
  - `nvim --headless -u NONE -c "set shadafile=NONE" -c "luafile tests/integration.lua" -c qa`
  - `nvim --headless -u NONE -c "set shadafile=NONE" -c "luafile tests/optional_kitty.lua" -c qa` (allowed optional failure signal)
  - `nvim --headless -u NONE -c "set shadafile=NONE" -c "luafile tests/run.lua" -c qa` (compat runner behavior)

### Acceptance criteria

- Three independent lanes exist and are runnable.
- `core_contract` lane is backend-independent and green in default environment.
- Optional kitty-specific behavior is isolated to `optional_kitty` lane.
- Existing coverage is preserved (no silent test loss).
- Updated docs clearly define lane purpose and invocation.

### Manual validation checklist

- Verify each previous major test area from `tests/run.lua` is mapped to a lane.
- Verify `tests/run.lua` still gives a sensible default developer experience.
- Verify docs clearly call out required lane(s) for merge gate.

### Rollback plan

- Revert lane split commits as a set:
  - restore single-file `tests/run.lua` runner,
  - remove new lane files and helper module.

### Phase 2 Progress Notes (Current Iteration)

- Added lane runner entrypoints:
  - `tests/core_contract.lua`
  - `tests/integration.lua`
  - `tests/optional_kitty.lua`
- Added shared harness helpers in:
  - `tests/_helpers.lua`
- Converted `tests/run.lua` into compatibility dispatcher:
  - runs `core_contract` + `integration`
  - runs optional kitty lane only when not explicitly skipped.
- Current lane behavior (verified):
  - `core_contract`: passes in default environment.
  - `integration`: passes in default environment.
  - `optional_kitty`: expected failure in non-kitty/default environment (`kitty escape emitted`), isolated from required lanes.
- Added targeted Sweep 5 minimum-gap tests in integration lane:
  - default notebook snake keymap registration contract,
  - snake keymap ownership transition contract (`default -> locked -> restored`),
  - snake temporary cell lifecycle contract (insert on start, delete on stop).
- Remaining for full Phase 2 closure:
  - optionally add README test-lane invocation snippet.
