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
# Manual Execution Stress Notebook
#
# This file is for interactive stress testing in NeoNotebooks.
# Run cells top-to-bottom.
#
# Includes:
# - deterministic batch compute workload (5000 calculations in batches of 100)
# - high-volume output workload
# - large local data fetch workload
# - optional real network fetch workload

# %% [code]
# Optional progress bar helper (falls back when tqdm is unavailable).
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
# Deterministic batch compute: 5000 calculations in batches of 100.
import time

start = time.perf_counter()
batch_size = 100
batches = 50
total = 0

for batch in iter_progress(range(batches), desc="batch-calc"):
    base = batch * batch_size
    subtotal = 0
    for i in range(base, base + batch_size):
        subtotal += ((i * i) + (3 * i)) % 97
    total += subtotal

elapsed = time.perf_counter() - start
EXPECTED_TOTAL = 239883
print("BATCH_DONE", total)
print("ELAPSED_SEC", round(elapsed, 4))
assert total == EXPECTED_TOTAL, f"unexpected checksum: {total} != {EXPECTED_TOTAL}"

# %% [code]
# High-volume stream output workload.
for i in range(2500):
    print(f"ROW:{i}")
print("STREAM_DONE")

# %% [code]
# Large local-data fetch workload (deterministic, no external network required).
import json
import tempfile
import urllib.request
from pathlib import Path

tmp_json = Path(tempfile.gettempdir()) / "neo_notebooks_perf_payload.json"
payload = {"rows": list(range(5000))}
tmp_json.write_text(json.dumps(payload), encoding="utf-8")

url = f"file://{tmp_json}"
with urllib.request.urlopen(url) as resp:
    data = json.loads(resp.read().decode("utf-8"))

print("FETCH_ROWS", len(data["rows"]))
assert len(data["rows"]) == 5000

# %% [code]
# Optional real network fetch (run only if you want external I/O stress).
# NOTE: This cell depends on internet connectivity.
import json
import urllib.request

with urllib.request.urlopen("https://httpbin.org/json", timeout=5) as resp:
    net_data = json.loads(resp.read().decode("utf-8"))

print("NET_OK", bool(net_data.get("slideshow")))
