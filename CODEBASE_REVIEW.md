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

## Documentation Gate Rules For Sweeps

Before merging sweep outputs into `main`:
- Update this file with concrete findings (not placeholders).
- Reconcile `TODO.md` (`Now/Next`) to reflect current sweep state.
- Update `TECHNICAL.md` when architectural contracts or module roles are clarified.
- If behavior or workflows are user-visible, also update `README.md`.

After each sweep implementation branch:
- Provide a short manual validation checklist when behavior changed.
- Do not merge/delete branch until explicit approval is given.
