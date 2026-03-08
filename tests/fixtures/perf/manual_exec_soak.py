# ---
# jupyter:
#   jupytext:
#     formats: ipynb,py:percent
#     text_representation:
#       extension: .py
#       format_name: percent
#       format_version: "1.3"
# ---

# %% [markdown]
# Manual Soak Stress Notebook (2-3 min target)
#
# This notebook is for sustained-load manual testing.
# It is intentionally heavier than `manual_exec_stress.*`.
#
# Suggested order:
# 1) setup + calibration
# 2) batch compute soak
# 3) large local fetch soak
# 4) optional stream soak
#
# Adjust knobs if runtime is too short/long on your machine.

# %% [code]
# Optional progress helper.
try:
    from tqdm import tqdm
except Exception:
    tqdm = None

def iter_progress(items, desc="work"):
    if tqdm is not None:
        return tqdm(items, desc=desc)
    return items

print("tqdm available:", tqdm is not None)

# %% [code]
# Knobs (tune for target runtime).
# Defaults are intentionally heavy (2-3 minute target on modern CPUs).
import time

TARGET_TOTAL_ITERS = 900_000_000
BATCH_SIZE = 2500
BATCHES = TARGET_TOTAL_ITERS // BATCH_SIZE
MIX = 131
MOD = 1_000_003
USE_TQDM = True
NON_TQDM_PROGRESS_STYLE = "bar"  # pct | ratio | bar

print("CONFIG", {
    "BATCHES": BATCHES,
    "BATCH_SIZE": BATCH_SIZE,
    "TOTAL_ITERS": BATCHES * BATCH_SIZE,
    "USE_TQDM": USE_TQDM,
    "NON_TQDM_PROGRESS_STYLE": NON_TQDM_PROGRESS_STYLE,
})

def emit_progress(prefix, completed, total, style="pct"):
    pct = int((completed / total) * 100)
    if style == "ratio":
        print(f"{prefix} {completed}/{total}")
        return
    if style == "bar":
        width = 20
        filled = int((completed / total) * width)
        bar = "#" * filled + "." * (width - filled)
        print(f"{prefix} [{bar}] {pct}% ({completed}/{total})")
        return
    print(f"{prefix} {pct}% ({completed}/{total})")

# %% [code]
# Multi-core soak variant (bypasses the GIL via processes).
# Run this cell if you want to intentionally saturate many CPU cores.
# You can lower WORKERS/CHUNKS if your machine becomes unresponsive.
import os
import multiprocessing as mp

WORKERS = max(1, (os.cpu_count() or 2) - 1)
CHUNKS = 4 * WORKERS
CHUNK_SIZE = 300_000

def _chunk_compute(start_i, count, mix, mod):
    acc_local = 0
    end_i = start_i + count
    for i in range(start_i, end_i):
        v = (i * i + mix * i + (i % 97) * (i % 193)) % mod
        acc_local = (acc_local + v) % mod
    return acc_local

def _worker(start_i, count, mix, mod, q):
    q.put(_chunk_compute(start_i, count, mix, mod))

start_mc = time.perf_counter()
total_mc = 0

methods = set(mp.get_all_start_methods())
if "fork" not in methods:
    print("MULTICORE_SKIP: fork start method unavailable on this platform")
else:
    ctx = mp.get_context("fork")
    q = ctx.Queue()
    procs = []
    for c in range(CHUNKS):
        start_i = c * CHUNK_SIZE
        p = ctx.Process(target=_worker, args=(start_i, CHUNK_SIZE, MIX, MOD, q))
        p.start()
        procs.append(p)

    completed = 0
    iterator = range(CHUNKS)
    if USE_TQDM:
        iterator = tqdm(iterator, total=CHUNKS, desc="soak-multicore")
    for _ in iterator:
        part = q.get()
        total_mc = (total_mc + part) % MOD
        completed += 1
        if (not USE_TQDM) and (completed % max(1, CHUNKS // 20) == 0):
            emit_progress("MULTICORE_PROGRESS", completed, CHUNKS, NON_TQDM_PROGRESS_STYLE)

    for p in procs:
        p.join()

elapsed_mc = time.perf_counter() - start_mc
print("MULTICORE_DONE", total_mc)
print("MULTICORE_ELAPSED_SEC", round(elapsed_mc, 3))

# %% [code]
# Heavy deterministic batch compute soak.
start = time.perf_counter()
acc = 0

iters = iter_progress(range(BATCHES), desc="soak-batch") if USE_TQDM else range(BATCHES)
progress_step = max(1, BATCHES // 20)

for b in iters:
    base = b * BATCH_SIZE
    subtotal = 0
    for i in range(base, base + BATCH_SIZE):
        # Deterministic mixed arithmetic workload.
        v = (i * i + MIX * i + (i % 97) * (i % 193)) % MOD
        subtotal = (subtotal + v) % MOD
    acc = (acc + subtotal) % MOD
    if (not USE_TQDM) and ((b + 1) % progress_step == 0):
        emit_progress("SOAK_PROGRESS", b + 1, BATCHES, NON_TQDM_PROGRESS_STYLE)

elapsed = time.perf_counter() - start
print("SOAK_DONE", acc)
print("SOAK_ELAPSED_SEC", round(elapsed, 3))

# %% [code]
# Large local fetch soak: synthesize + read a large JSON payload via file://.
# Increase FETCH_ROWS for heavier JSON decode/load cost.
import json
import tempfile
import urllib.request
from pathlib import Path
import time

FETCH_ROWS = 1000000
tmp_json = Path(tempfile.gettempdir()) / "neo_notebooks_perf_soak_payload.json"

start_write = time.perf_counter()
payload = {"rows": list(range(FETCH_ROWS))}
tmp_json.write_text(json.dumps(payload), encoding="utf-8")
write_elapsed = time.perf_counter() - start_write

start_fetch = time.perf_counter()
url = f"file://{tmp_json}"
with urllib.request.urlopen(url) as resp:
    data = json.loads(resp.read().decode("utf-8"))
fetch_elapsed = time.perf_counter() - start_fetch

print("FETCH_ROWS", len(data["rows"]))
print("WRITE_SEC", round(write_elapsed, 3))
print("FETCH_SEC", round(fetch_elapsed, 3))
assert len(data["rows"]) == FETCH_ROWS

# %% [code]
# Optional stream soak (can generate massive output; run only if desired).
# Set STREAM_ROWS lower if UI gets sluggish.
STREAM_ROWS = 50000
for i in range(STREAM_ROWS):
    print(f"SOAK_ROW:{i}")
print("SOAK_STREAM_DONE", STREAM_ROWS)
