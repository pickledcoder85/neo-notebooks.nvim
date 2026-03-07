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
