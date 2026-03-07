# Architecture Flowcharts

Living visual map of current architecture and planned refactor state.

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
| (central orchestrator)       |
+------------------------------+
      |           |          |
      |           |          |
      |           |          +----------------------+
      |           |                                 |
      v           v                                 v
+-----------+ +-----------+                 +---------------+
| actions   | | exec      |                 | format I/O    |
| .lua      | | .lua      |                 | ipynb.lua     |
+-----------+ +-----------+                 +---------------+
      |           |                                 |
      | edits     | output payloads                 | import/export model
      v           v                                 v
+-----------+ +-----------+                 +---------------+
| index     | | output    |---------------->| render        |
| .lua      | | .lua      |  render request | .lua          |
+-----------+ +-----------+                 +---------------+
                                                |
                                                | extmarks / virt text
                                                v
                                      +----------------------+
                                      | NEOVIM BUFFER + UI   |
                                      +----------------------+
```

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
+---------------------+   +-------------------+   +----------------------+
| tests/core_contract |   | tests/integration |   | tests/optional_kitty |
+---------------------+   +-------------------+   +----------------------+
          |                         |                          |
          +----------- independent confidence lanes -----------+
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
                    | thin bootstrap only          |
                    +-----------------------------+
                         |        |        |
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
+----------------+   +-------------------+
              \           /
               \         /
                v       v
              +------------------+
              | EXECUTION LAYER  |
              | python job+queue |
              +------------------+
```
