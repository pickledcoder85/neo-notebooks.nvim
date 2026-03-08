# Architecture Flowcharts

Living visual map of current architecture and planned refactor state.

## Phase Progress

- Phase 1 (Contract Baseline): complete on `feature/review-sweep-1-contracts` (docs-only).
- Phase 2 (Test Lane Split): complete (lane runners added; optional kitty isolated; lifecycle/keymap minimum tests added; lane invocation docs added).
- Phase 3 (Entrypoint Decomposition): complete (keymap/lifecycle/command extraction + bootstrap wiring landed).
- Phase 4 (Mutation/Render Contract): complete (shared mutation helper + named mutation modes + migrated high-traffic call sites).
- Phase 5 (Format Layer Split): complete (Jupytext parser + output codec + ipynb codec + buffer adapter split).
- Phase 6 (Error/Notify Policy): complete (boundary-owned notify flows for commands/keymaps/lifecycle; internal notify paths reduced to explicit debug-gated diagnostics).
- Phase 7 (Kernel/Session Robustness): complete (state owner + transitions + kernel controls + queue-pause dispatch gating + bounded dispatch-time recovery + optional virtual badge + dead-active-request reconciliation).
- Phase 8 (Performance/Scalability Lane): complete (synthetic large fixtures + optional performance lane + profile-based threshold policy and budget scaling controls landed).
- Streaming execution output protocol (incremental stdout/stderr with carriage-return line replacement) landed for long-running cell UX.
- Streaming path now includes render-pressure controls (preview cap + throttled refresh cadence) to protect UI responsiveness.
- Streaming-depth v1: live stream preview now merges by event arrival order (cross-stream), uses a single global preview cap, and supports configurable execution placeholder text.
- Streaming UX defaults v1: recognized non-`tqdm` progress lines are now policy-formatted (default `bar`) in both live preview and final output formatting.
- Kernel robustness phase 2: dead active-request reconciliation now clears stale `active_request` when kernel exits mid-flight and transitions state to `error` before next-request recovery.
- Interop reliability v1: `.ipynb` decode path now validates top-level/cells shapes and normalizes imported cell payloads (unknown type fallback + string-source normalization).
- Interop reliability v2: `.ipynb` decode path now rejects object-shaped `cells` maps and normalizes malformed code outputs to list-safe defaults for export stability.

## Reading Guide

- Boxes are modules/components.
- Arrows show call direction.
- Labels on arrows describe what is passed.
- Start at `ENTRY` diagrams, then drill into phase diagrams.

---

## 1) Current System (Digestible View)

### 1.1 Entry and Control Flow

```text
+------------------------------+
|         USER ACTION          |
| commands / keymaps / events  |
+------------------------------+
               |
               | triggers
               v
+------------------------------+
| plugin/neo_notebooks.lua     |
| (gating + helper functions)  |
+------------------------------+
               |
               | delegates wiring
               v
+------------------------------+
| entrypoint/init.lua          |
| bootstrap: register commands |
| + keymaps + lifecycle        |
+------------------------------+
      |           |          |
      v           v          v
+-----------+ +-----------+ +-----------+
|commands   | | keymaps   | | lifecycle |
|.lua       | | .lua      | | .lua      |
+-----------+ +-----------+ +-----------+
      \           |          /
       \          |         /
        v         v        v
       +----------------------+
       | domain/render/exec   |
       | + format modules     |
       +----------------------+
                |
                | extmarks / virt text
                v
      +----------------------+
      | NEOVIM BUFFER + UI   |
      +----------------------+
```

`entrypoint/init.lua` is the bootstrap coordinator: it wires the three registration modules (`commands.lua`, `keymaps.lua`, `lifecycle.lua`) using shared helper callbacks from `plugin/neo_notebooks.lua`, so plugin behavior stays the same while ownership is separated.

### 1.2 State Planes (What is Stored Where)

```text
+--------------------+      +------------------------+
| buffer text lines  |<---->| cells/actions/ipynb    |
+--------------------+      +------------------------+
          |
          | indexed as cell ranges + ids
          v
+--------------------+      +------------------------+
| index state        |<---->| render/output/scheduler|
| (extmark ids,      |      |                        |
|  dirty/layout)     |      +------------------------+
+--------------------+

+--------------------+      +------------------------+
| vim.b buffer vars  |<---->| plugin/ipynb/exec/etc  |
| (flags + metadata) |      | (shared runtime state) |
+--------------------+      +------------------------+

+--------------------+      +------------------------+
| async runtime      |<---->| exec queue / timers    |
| (jobs/timers)      |      | spinner / snake        |
+--------------------+      +------------------------+
```

---

## 2) Refactor Phases (Current -> Target)

## Phase 1: Contract Baseline (Docs Only)

Current: contracts are implicit and spread across code/comments, which makes onboarding and safe refactoring harder.  
Why not ideal: module boundaries and invariants are easy to misinterpret, so changes can break behavior unintentionally.  
Target: explicit contract tables, event-flow maps, buffer-state schema, and UI behavior matrix.  
Benefit: shared understanding of APIs/ownership and lower regression risk before structural changes.
Definition of done: all four contract artifacts are published and referenced by `TECHNICAL.md`/`TODO.md`.

Current:
```text
+-----------------------------+
| implicit contracts in code  |
+-----------------------------+
```

Target:
```text
+-----------------------------+      +-----------------------------+
| module contract table       |      | buffer-state schema         |
+-----------------------------+      +-----------------------------+
               \                          /
                \                        /
                 v                      v
               +-----------------------------+
               | event-flow + UI matrix      |
               +-----------------------------+
```

---

## Phase 2: Test Lane Split

Current: one broad test entrypoint mixes core and optional backend paths.  
Why not ideal: optional-path failures can hide core correctness signal and slow iteration.  
Target: separate `core`, `integration`, and `optional` test lanes.  
Benefit: faster feedback loops and clearer pass/fail meaning per change type.
Definition of done: three independent test entrypoints exist and core lane runs clean without optional backends.

Current:
```text
+------------------+
| tests/run.lua    |
| single entrypoint|
+------------------+
```

Target:
```text
+---------------------+   +-------------------+   +----------------------+   +-------------------+
| tests/core_contract |   | tests/integration |   | tests/optional_kitty |   | tests/performance |
+---------------------+   +-------------------+   +----------------------+   +-------------------+
          |                         |                          |                         |
          +-------------------------+--------------------------+-------------------------+
                                            independent confidence lanes
```

Performance lane + fixture flow:
```text
+-----------------------------+
| tests/fixtures/perf/*       |
| large_percent.py            |
| large_notebook.ipynb        |
+-----------------------------+
               |
               v
+-----------------------------+
| tests/performance.lua       |
| import -> rebuild -> render |
| -> export timing budgets    |
| + batch/stream/fetch exec   |
+-----------------------------+
               |
               v
+-----------------------------+
| regression signal           |
| (latency budget checks)     |
+-----------------------------+
```

Streaming event flow (current):
```text
+-----------------------------+
| Python _NeoStream           |
| emits {kind=stream, seq}    |
+-----------------------------+
               |
               v
+-----------------------------+
| exec.apply_stream_event     |
| append/replace event list   |
| apply progress style policy |
| trim global preview cap     |
+-----------------------------+
               |
               v
+-----------------------------+
| output.show_inline          |
| line1=placeholder+spinner   |
| line2+=live stream preview  |
+-----------------------------+
```

---

## Phase 3: Entrypoint Decomposition

Current: plugin entrypoint handles commands, keymaps, lifecycle, and feature glue together.  
Why not ideal: high coupling increases blast radius of small edits and makes ownership unclear.  
Target: thin bootstrap with separated command/lifecycle/keymap wiring modules.  
Benefit: simpler mental model, cleaner APIs, and safer incremental refactors.
Definition of done: entrypoint is bootstrap-only and extracted modules own command/lifecycle/keymap registration.

Current:
```text
+--------------------------------------+
| plugin/neo_notebooks.lua             |
| commands + autocmds + keymaps + glue |
+--------------------------------------+
```

Target:
```text
                    +-----------------------------+
                    | plugin/neo_notebooks.lua    |
                    | gating + helper callbacks    |
                    +-----------------------------+
                             |
                             v
                    +-----------------------------+
                    | entrypoint/init.lua         |
                    | bootstrap/wiring hub        |
                    +-----------------------------+
                         |        |        |
                         v        v        v
                 +-----------+ +-----------+ +-----------+
                 | commands  | | lifecycle | | keymaps   |
                 +-----------+ +-----------+ +-----------+
                         \         |         /
                          \        |        /
                           v       v       v
                         +-------------------+
                         | feature wiring    |
                         +-------------------+
```

---

## Phase 4: Mutation/Render Contract

Current: edit paths manually sequence line edits, dirty marks, and render scheduling.  
Why not ideal: duplicated sequencing logic can drift and create subtle consistency bugs.  
Target: shared mutation boundary enforcing canonical edit -> dirty -> schedule flow.  
Benefit: consistent behavior, fewer edge-case regressions, and easier performance tuning.
Definition of done: high-traffic mutation call sites use shared mutation helper(s) with validated sequencing.

Current:
```text
many places do:
  edit lines -> mark_dirty -> render/schedule
```

Target:
```text
+-------------------------------+
| mutation helper boundary      |
| mutate(edit_spec, opts)       |
+-------------------------------+
            |
            | enforces sequence
            v
   +-------------------------+
   | 1) apply edit           |
   | 2) mark dirty/index hint|
   | 3) schedule render      |
   +-------------------------+
```

---

## Phase 5: Format Layer Split

Current: one format module combines codec logic, parser logic, metadata policy, and buffer adaptation.  
Why not ideal: mixed concerns make maintenance and testing harder as format support grows.  
Target: split codec/parser/adapter into focused modules around a canonical notebook model.  
Benefit: clearer APIs, isolated tests, and easier extension to additional formats.
Definition of done: codec, parser, and buffer adapter are separate modules with unchanged user-visible behavior.

Current:
```text
+-------------------------------+
| ipynb.lua                     |
| codec + jupytext + adapter    |
+-------------------------------+
```

Target:
```text
+-------------------+   +-----------------------+   +----------------------+
| ipynb_codec.lua   |   | jupytext_percent.lua  |   | notebook_format_io   |
| json <-> model    |   | percent <-> model     |   | buffer-facing adapter|
+-------------------+   +-----------------------+   +----------------------+
             \                   /                          |
              \                 /                           | called by commands
               v               v                            v
                +----------------------------------------------+
                | canonical notebook model in memory           |
                +----------------------------------------------+
```

---

## Phase 6: Error/Notify Policy

Current: error handling mixes return-values, direct notifications, and silent recovery patterns.  
Why not ideal: inconsistent behavior reduces debuggability and makes failures less predictable.  
Target: internal modules return errors; command boundaries own user-facing notifications; debug logs are gated.  
Benefit: uniform failure semantics, better observability, and cleaner call contracts.
Definition of done: documented error-policy is applied across touched modules and command boundaries are the only notify surface.

Current:
```text
mixed return + notify + pcall patterns
```

Target:
```text
+-------------------------+       +----------------------------+
| internal modules        |       | command boundary           |
| return (ok, err)        | ----> | vim.notify user-facing msg |
+-------------------------+       +----------------------------+
                |
                v
      +----------------------+
      | debug logs behind    |
      | explicit debug flags |
      +----------------------+
```

---

## Phase 7: Kernel/Session State Machine and Recovery

Current: session readiness is inferred from queue/job behavior instead of an explicit user-visible state contract.  
Why not ideal: interrupt/restart/failure paths can feel ambiguous when state transitions race with queued requests.  
Target: explicit per-buffer execution state machine with validated transitions and bounded recovery policy.  
Benefit: deterministic behavior, clearer UX, and tighter tests for failure handling.
Definition of done: state transitions are documented, implemented, and covered by integration tests.

Current:
```text
run request
  |
  v
queue/session checks (implicit)
  |
  +--> dispatch
  +--> maybe restart
  +--> maybe fail
```

Target:
```text
+------------------------------+
| session_state (per buffer)   |
| idle/running/interrupting/   |
| restarting/error             |
+------------------------------+
      |        |         |
      |        |         +--> validates transition + reason
      |        v
      |   exec/session paths
      |   (enqueue/dispatch/interrupt/restart/resp)
      v
boundary notifications + status UX
      ^
      |
<leader>k* kernel controls
(kr/ki/ks/kp/kk via keymaps)

status surfaces:
  - statusline API (lualine/custom): kernel_status()
  - optional virtual badge (default off)
```

---

## 3) One Concrete Flow (Easy Trace)

### Jupytext Import - Current

```text
USER
  |
  v
NeoNotebookImportJupytext command
  |
  v
plugin/neo_notebooks.lua
  |
  v
ipynb.import_jupytext
  |
  +--> write buffer lines
  +--> rebuild/mark index
  +--> set metadata in vim.b
  |
  v
render_if_enabled
  |
  v
render extmarks/UI
```

### Jupytext Import - Target

```text
USER
  |
  v
commands.lua handler
  |
  v
notebook_format_io.import_jupytext_to_buffer
  |
  +--> decode_jupytext_percent -> notebook model
  +--> mutation helper applies model
  +--> standardized mark+schedule
  |
  v
lifecycle/keymap adapter
  |
  v
render pipeline (same user behavior, cleaner contracts)
```

---

## 4) Target Layered Architecture (Final Shape)

```text
+-----------------------------+
| UI/LIFECYCLE LAYER          |
| commands, keymaps, autocmds |
+-----------------------------+
              |
              v
+-----------------------------+
| DOMAIN LAYER                |
| actions, run_all/subset,    |
| session, navigation         |
+-----------------------------+
              |
              v
+-----------------------------+
| STATE/CONTRACT LAYER        |
| index, mutation, buffer     |
| state schema                |
+-----------------------------+
       |                 |
       |                 |
       v                 v
+----------------+   +-------------------+
| RENDER LAYER   |   | FORMAT LAYER      |
| render/output/ |   | ipynb codec +     |
| spinner/overlay|   | jupytext parser   |
| badge/padding  |   |                   |
+----------------+   +-------------------+
              \           /
               \         /
                v       v
              +------------------+
              | EXECUTION LAYER  |
              | python job+queue |
              +------------------+
```
