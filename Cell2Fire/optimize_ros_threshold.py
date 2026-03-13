#!/usr/bin/env python3
"""One-at-a-time black-box optimizer for the ROS threshold.

This script repeatedly runs the Cell2Fire binary with different
`--ROS-Threshold` values, parses the reported burn statistics, and narrows
in on the threshold that optimizes a chosen objective (e.g., maximizing the
number of burnt cells).  It implements a simple adaptive grid search: each
iteration samples several thresholds across the current window, records the
result, then shrinks the window around the best-performing value.
"""
from __future__ import annotations

import argparse
import csv
import math
import random
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

STAT_PATTERN = re.compile(r"^\s*(Available|Burnt|Non-Burnable|Firebreak)\s+(\d+)\s+([0-9.]+)%")

class SimulationError(RuntimeError):
    pass

def parse_stats(stdout: str) -> Dict[str, Tuple[int, float]]:
    stats: Dict[str, Tuple[int, float]] = {}
    for line in stdout.splitlines():
        match = STAT_PATTERN.match(line)
        if match:
            status, count, percent = match.groups()
            stats[status] = (int(count), float(percent))
    if "Burnt" not in stats:
        raise SimulationError("Failed to parse Burnt row from simulator output")
    return stats

def run_simulation(binary: Path, data_path: Path, simulator: str, threshold: float,
                   extra_args: List[str]) -> Dict[str, Tuple[int, float]]:
    cmd = [str(binary), "--sim", simulator,
           "--input-instance-folder", str(data_path),
           "--ROS-Threshold", f"{threshold:.4f}"] + extra_args
    completed = subprocess.run(cmd, capture_output=True, text=True)
    if completed.returncode != 0:
        raise SimulationError(f"Command failed (exit {completed.returncode}):\n{completed.stderr or completed.stdout}")
    return parse_stats(completed.stdout)

def evaluate_objective(stats: Dict[str, Tuple[int, float]], objective: str) -> float:
    if objective == "burnt":
        return stats["Burnt"][0]
    if objective == "available":
        return -stats.get("Available", (0,))[0]
    if objective == "minimize_burnt":
        return -stats["Burnt"][0]
    raise ValueError(f"Unknown objective {objective}")

def linspace(start: float, stop: float, num: int) -> Iterable[float]:
    if num == 1:
        yield (start + stop) / 2
        return
    step = (stop - start) / (num - 1)
    for i in range(num):
        yield start + i * step

def adaptive_search(args: argparse.Namespace) -> None:
    binary = Path(args.binary).resolve()
    data_path = Path(args.data_path).resolve()
    if not binary.exists():
        raise FileNotFoundError(binary)
    if not data_path.exists():
        raise FileNotFoundError(data_path)

    results: Dict[float, Dict[str, Tuple[int, float]]] = {}
    window_min, window_max = args.min_threshold, args.max_threshold
    best_threshold = None
    best_score = -math.inf

    for iteration in range(1, args.iterations + 1):
        thresholds = list(linspace(window_min, window_max, args.samples_per_iter))
        print(f"Iteration {iteration}: testing thresholds {thresholds}")
        for th in thresholds:
            if th in results:
                continue
            try:
                stats = run_simulation(binary, data_path, args.sim, th, args.extra_args)
            except SimulationError as exc:
                print(f"[WARN] Threshold {th:.4f} failed: {exc}")
                continue
            results[th] = stats
            score = evaluate_objective(stats, args.objective)
            print(f"  th={th:.4f} -> Burnt={stats['Burnt'][0]} (score={score})")
            if score > best_score:
                best_score = score
                best_threshold = th
        if best_threshold is None:
            print("No successful simulations yet; stopping")
            break
        span = window_max - window_min
        window_min = max(args.min_threshold, best_threshold - span / (2 * args.refine_factor))
        window_max = min(args.max_threshold, best_threshold + span / (2 * args.refine_factor))

    if best_threshold is None:
        print("No successful runs; exiting")
        return

    print(f"\nBest threshold ≈ {best_threshold:.4f} (score={best_score})")
    if args.csv:
        with open(args.csv, "w", newline="") as fh:
            writer = csv.writer(fh)
            writer.writerow(["threshold", "available", "burnt", "non_burnable", "firebreak"])
            for th in sorted(results):
                stats = results[th]
                writer.writerow([
                    f"{th:.4f}",
                    stats.get("Available", (0,))[0],
                    stats.get("Burnt", (0,))[0],
                    stats.get("Non-Burnable", (0,))[0],
                    stats.get("Firebreak", (0,))[0],
                ])
        print(f"Saved evaluations to {args.csv}")

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Black-box search for the ROS threshold")
    parser.add_argument("--binary", default="./Cell2Fire", help="Path to Cell2Fire executable")
    parser.add_argument("--data-path", required=True, help="Input instance folder")
    parser.add_argument("--sim", default="S", help="Simulator code (S, K, C, P)")
    parser.add_argument("--min-threshold", type=float, default=0.0)
    parser.add_argument("--max-threshold", type=float, default=4.0)
    parser.add_argument("--iterations", type=int, default=4)
    parser.add_argument("--samples-per-iter", type=int, default=5)
    parser.add_argument("--refine-factor", type=float, default=2.0,
                        help="Larger values shrink the window more aggressively")
    parser.add_argument("--objective", choices=["burnt", "available", "minimize_burnt"],
                        default="burnt")
    parser.add_argument("--csv", help="Optional CSV path for exporting all evaluations")
    parser.add_argument("extra_args", nargs=argparse.REMAINDER,
                        help="Additional flags passed verbatim to Cell2Fire")
    return parser

if __name__ == "__main__":
    adaptive_search(build_parser().parse_args())
