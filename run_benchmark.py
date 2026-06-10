#!/usr/bin/env python3
"""
STREAM memory bandwidth benchmark runner.

One unit of work = one execution of stream_c.exe, which runs the four
memory-bandwidth kernels (Copy / Scale / Add / Triad) and reports the
best observed bandwidth (MB/s) per kernel across STREAM_NTIMES internal
iterations.

timeit.repeat drives the outer loop: NUMBER executions per trial,
REPEAT independent trials.  STREAM's own reported MB/s is the primary
metric; wall-clock time per run is included for reference.
"""

import json
import math
import re
import subprocess
import sys
import timeit
from datetime import datetime, timezone

# ── Configuration ─────────────────────────────────────────────────────────────
NUMBER             = 1           # STREAM executions per trial  (calls per trial)
REPEAT             = 5           # number of independent trials
STREAM_ARRAY_SIZE  = 10_000_000  # array elements — set ≥ 4× your L3 cache size
STREAM_NTIMES      = 10          # internal iterations inside STREAM per run
BINARY             = "stream_c.exe"
SOURCE             = "stream.c"
OUTPUT_FILE        = "artemis_results.json"
# ─────────────────────────────────────────────────────────────────────────────

KERNELS = ("Copy", "Scale", "Add", "Triad")

_BW_RE = re.compile(
    r"^(Copy|Scale|Add|Triad):\s+([\d.]+)",
    re.MULTILINE,
)
_THREADS_RE = re.compile(r"Number of Threads counted\s*=\s*(\d+)")


# ── Statistics (stdlib only) ─────────────────────────────────────────────────

def _mean(xs: list) -> float:
    return sum(xs) / len(xs)


def _std(xs: list) -> float:
    if len(xs) < 2:
        return 0.0
    m = _mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))


# ── Helpers ──────────────────────────────────────────────────────────────────

def compile_binary() -> None:
    """Compile stream_c.exe (excluded from timing)."""
    proc = subprocess.run(
        [
            "gcc", "-O2", "-fopenmp",
            f"-DSTREAM_ARRAY_SIZE={STREAM_ARRAY_SIZE}",
            f"-DNTIMES={STREAM_NTIMES}",
            SOURCE, "-o", BINARY,
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"Compilation failed:\n{proc.stderr.strip()}")
    print(f"Compiled {BINARY}  "
          f"(array_size={STREAM_ARRAY_SIZE:,}, ntimes={STREAM_NTIMES})")


def run_once() -> str:
    """Run stream_c.exe once; return stdout."""
    proc = subprocess.run(
        [f"./{BINARY}"], capture_output=True, text=True
    )
    if proc.returncode != 0:
        sys.exit(f"Benchmark run failed:\n{proc.stderr.strip()}")
    return proc.stdout


def parse_bandwidth(output: str) -> dict:
    return {m.group(1): float(m.group(2)) for m in _BW_RE.finditer(output)}


def detect_threads(output: str) -> int:
    m = _THREADS_RE.search(output)
    return int(m.group(1)) if m else 0


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    # ── Setup (excluded from timing) ─────────────────────────────────────────
    compile_binary()

    warmup_out = run_once()
    omp_threads = detect_threads(warmup_out)
    print(f"Warm-up run complete.  OMP threads detected: {omp_threads}")

    # timeit.repeat cannot return values, so we collect side-effects here.
    # Each _stmt() call appends one stdout string.
    captured: list = []

    def _stmt() -> None:
        captured.append(run_once())

    # ── Measurement ───────────────────────────────────────────────────────────
    print(f"\nRunning {REPEAT} trials x {NUMBER} call(s) per trial ...\n")
    trial_times = timeit.repeat(_stmt, number=NUMBER, repeat=REPEAT)

    # ── Aggregate ─────────────────────────────────────────────────────────────
    # trial i owns captured[i*NUMBER : (i+1)*NUMBER]
    wall_per_run: list = []
    bw_per_run: dict = {k: [] for k in KERNELS}

    for i in range(REPEAT):
        wall_per_run.append(trial_times[i] / NUMBER)
        for output in captured[i * NUMBER : (i + 1) * NUMBER]:
            bw = parse_bandwidth(output)
            for k in KERNELS:
                if k in bw:
                    bw_per_run[k].append(bw[k])

    # ── Format & print ────────────────────────────────────────────────────────
    col_w = 28
    print(f"  {'Metric':<{col_w}} {'Mean':>14}  {'Std':>14}  Unit")
    print("  " + "-" * (col_w + 34))

    metrics: dict = {}

    def record(name: str, values: list, unit: str) -> None:
        m, s = _mean(values), _std(values)
        metrics[name] = {"mean": round(m, 4), "std": round(s, 4), "unit": unit}
        print(f"  {name:<{col_w}} {m:>14.2f}  {s:>14.2f}  {unit}")

    record("wall_time_s",  wall_per_run,     "s / run")
    for k in KERNELS:
        record(f"{k}_MB_s", bw_per_run[k], "MB/s")

    print("  " + "-" * (col_w + 34))
    print(f"  number={NUMBER}, repeat={REPEAT}")

    # ── Write JSON ────────────────────────────────────────────────────────────
    output = {
        "benchmark":  "STREAM",
        "timestamp":  datetime.now(timezone.utc).isoformat(),
        "config": {
            "number":            NUMBER,
            "repeat":            REPEAT,
            "stream_array_size": STREAM_ARRAY_SIZE,
            "stream_ntimes":     STREAM_NTIMES,
            "omp_threads":       omp_threads,
            "binary":            BINARY,
        },
        "metrics": metrics,
    }

    with open(OUTPUT_FILE, "w") as f:
        json.dump(output, f, indent=2)
    print(f"\nResults written to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
