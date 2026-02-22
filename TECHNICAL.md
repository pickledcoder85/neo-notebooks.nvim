# Technical Notes

This document summarizes implementation choices and the evolution of core features.

## Architecture overview

- `plugin/neo_notebooks.lua`
  - Registers user commands.
  - Sets buffer-local keymaps.
  - Runs auto-render via autocommands.
  - Stops Python sessions when buffers are wiped.
- `lua/neo_notebooks/cells.lua`
  - Parses cell markers (`# %% [code|markdown]`).
  - Identifies the current cell and inserts new cells.
- `lua/neo_notebooks/render.lua`
  - Draws virtual borders around cells using `virt_lines`.
  - Adds a virtual label indicating cell type.
- `lua/neo_notebooks/exec.lua`
  - Manages a persistent Python process per buffer.
  - Executes cell code and collects output.
  - Displays output in a floating window.

## Execution model

- Each buffer has a dedicated Python process started with `python -u -c <server>`.
- The Lua side sends JSON lines: `{ "id": n, "code": "..." }`.
- The Python side executes code in a shared `globals_dict` so state persists across cells.
- If the last statement is an expression, it is evaluated and printed (Jupyter-like).

## Output handling

- Output is shown in a minimal floating window at the bottom-right of the editor.
- The output buffer is `nofile` and `bufhidden=wipe`.
- The window closes on `q` or `<Esc>`.

## Auto-render and keymaps

- Auto-render is gated by:
  - `filetypes` (default `{ "python" }`).
  - Optional `require_markers` to render only when markers are present.
- Keymaps are buffer-local and only set when buffers pass the gating rules.

## Future work

- Add a proper markdown renderer for headings/emphasis.
- Provide navigation and cell list UI.
- Add `.ipynb` import/export.
- Add Lua tests for parsing and execution.
