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
# Start conservative; increase until this takes ~2-3 minutes.
import time

BATCHES = 1200
BATCH_SIZE = 2500
MIX = 131
MOD = 1_000_003

print("CONFIG", {"BATCHES": BATCHES, "BATCH_SIZE": BATCH_SIZE, "TOTAL_ITERS": BATCHES * BATCH_SIZE})

# %% [code]
# Heavy deterministic batch compute soak.
start = time.perf_counter()
acc = 0

for b in iter_progress(range(BATCHES), desc="soak-batch"):
    base = b * BATCH_SIZE
    subtotal = 0
    for i in range(base, base + BATCH_SIZE):
        # Deterministic mixed arithmetic workload.
        v = (i * i + MIX * i + (i % 97) * (i % 193)) % MOD
        subtotal = (subtotal + v) % MOD
    acc = (acc + subtotal) % MOD

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

FETCH_ROWS = 300000
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
