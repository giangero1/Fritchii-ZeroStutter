#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Summarize a bounded local emulator log without exporting raw log text or paths.

Pacer maxima describe windows. DKB renderer/GPU frame records are rate-limited
samples in this source tree, so neither provides a complete frame-stall count.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import statistics


STAMP = re.compile(r"^\[\s*([0-9.]+)\]")
SUMMARY = re.compile(
    r"Runtime pipelines in the last 10 s: (\d+) built, ([\d.]+) ms on the GPU thread "
    r"\(([\d.]+) ms of it graphics SPIR-V\), ([\d.]+) ms graphics SPIR-V on workers, "
    r"([\d.]+) ms of draws held for unbuilt pipelines"
)
BUILD = re.compile(r"(Graphics|Compute) pipeline built on the GPU thread in ([\d.]+) ms")
PACER = re.compile(
    r"Host pacing (?:on|off): (\d+) frames at ([\d.]+) Hz;.*?"
    r"interval mean ([\d.]+) ms, max ([\d.]+)"
)


def timing(values: list[float]) -> dict:
    return {
        "records": len(values),
        "sum_ms": round(sum(values), 3),
        "median_ms": statistics.median(values) if values else None,
        "max_ms": max(values) if values else None,
        "observed_over_500ms": sum(value > 500 for value in values),
    }


def new_session(build_sha: str | None = None) -> dict:
    return {
        "build_sha": build_sha,
        "program_id": None,
        "first_observed_seconds": None,
        "last_observed_seconds": None,
        "lines_in_time_range": 0,
        "pipeline_summary": {
            "records": 0, "builds": 0, "gpu_thread_ms": 0.0,
            "graphics_spirv_gpu_thread_ms": 0.0,
            "graphics_spirv_worker_ms": 0.0, "graphics_draw_hold_ms": 0.0,
            "scope": "Non-overlapping counters emitted on a build after >=10 seconds; not fixed-duration windows.",
        },
        "disk_load_queued_pipeline_counts": [],
        "error_counts": Counter(),
        "pacer": {"window_records": 0, "max_window_interval_ms": None,
                  "max_window_ending_seconds": None, "windows_with_max_over_500ms": 0,
                  "frames_over_500ms": None,
                  "scope": "Window aggregates; exact frame-stall counts unavailable."},
        "gpu_profile": {"records": 0},
        "eviction_messages": 0,
        "_graphics": [], "_compute": [], "_renderer": [], "_gpu_frame": [],
    }


def analyze(lines, *, since: float = 0.0, until: float | None = None) -> dict:
    sessions = []
    current = new_session()
    for line in lines:
        stamp = STAMP.match(line)
        if not stamp:
            continue  # Includes a truncated leading/trailing fragment.
        seconds = float(stamp[1])
        if "Lichii Version:" in line:
            if current["lines_in_time_range"]:
                sessions.append(current)
            # Export only a commit identifier, never the potentially private build/path text.
            sha = re.search(r"(?:nx2-|audit-|\b)([a-fA-F0-9]{7,40})(?=\s|$)", line)
            current = new_session(sha[1].lower() if sha else None)
        boot = re.search(r"Booting game:\s*(?:0x)?([a-fA-F0-9]{16})(?![a-fA-F0-9])", line)
        if boot:
            if current["program_id"] is not None:
                previous_sha = current["build_sha"]
                if current["lines_in_time_range"]:
                    sessions.append(current)
                current = new_session(previous_sha)
            current["program_id"] = boot[1].upper()
        if seconds < since or (until is not None and seconds > until):
            continue
        current["lines_in_time_range"] += 1
        if current["first_observed_seconds"] is None:
            current["first_observed_seconds"] = seconds
        current["last_observed_seconds"] = seconds
        match = SUMMARY.search(line)
        if match:
            summary = current["pipeline_summary"]
            summary["records"] += 1
            for key, number in zip(
                ("builds", "gpu_thread_ms", "graphics_spirv_gpu_thread_ms",
                 "graphics_spirv_worker_ms", "graphics_draw_hold_ms"), match.groups()
            ):
                summary[key] += int(number) if key == "builds" else float(number)
        match = BUILD.search(line)
        if match:
            current["_" + match[1].lower()].append(float(match[2]))
        match = PACER.search(line)
        if match:
            pacer, maximum = current["pacer"], float(match[4])
            pacer["window_records"] += 1
            pacer["windows_with_max_over_500ms"] += maximum > 500
            if pacer["max_window_interval_ms"] is None or maximum > pacer["max_window_interval_ms"]:
                pacer["max_window_interval_ms"] = maximum
                pacer["max_window_ending_seconds"] = seconds
        match = re.search(r"Total Pipeline Count: (\d+)", line)
        if match:
            current["disk_load_queued_pipeline_counts"].append(int(match[1]))
        if re.search(r"\b(?:GPU thread|GPU back thread) per second:", line):
            current["gpu_profile"]["records"] += 1
        if "DKB renderer renderer_frame=" in line:
            match = re.search(r"\bcpu_frame_wall_ms=([\d.-]+)", line)
            if match and float(match[1]) >= 0:
                current["_renderer"].append(float(match[1]))
        if "DKB gpu_frame renderer_frame=" in line:
            match = re.search(r"\bgpu_frame_span_ms=([\d.-]+)", line)
            if match and float(match[1]) >= 0:
                current["_gpu_frame"].append(float(match[1]))
        if re.search(r"Evicted \d+ graphics pipelines", line):
            current["eviction_messages"] += 1
        if "<Error>" in line or "<Critical>" in line:
            category = "other"
            lower = line.lower()
            for needle, label in (
                ("unmapped device readblock", "unmapped_device_read"),
                ("device_lost", "device_lost"), ("device lost", "device_lost"),
                ("out_of_host_memory", "allocation_or_memory"),
                ("out_of_device_memory", "allocation_or_memory"),
                ("out of memory", "allocation_or_memory"),
                ("pipeline build failed", "pipeline_build_failure"), ("stubbed", "stubbed_service"),
            ):
                if needle in lower:
                    category = label
                    break
            current["error_counts"][category] += 1
    if current["lines_in_time_range"]:
        sessions.append(current)
    for session in sessions:
        session["logged_runtime_builds"] = {
            kind: timing(session.pop("_" + kind)) for kind in ("graphics", "compute")
        }
        session["logged_runtime_builds"]["scope"] = (
            "Thresholded build records: first 400 over 2 ms and all over 100 ms; "
            "not all builds and not frame intervals. Do not add these sums to summary work."
        )
        session["sampled_frame_records"] = {
            "renderer_cpu_intervals": timing(session.pop("_renderer")),
            "gpu_frame_spans": timing(session.pop("_gpu_frame")),
            "complete_frame_count_over_500ms": None,
            "scope": "DKB records are rate-limited samples; observed counts cover samples only, not all frames.",
        }
        for key, value in session["pipeline_summary"].items():
            if isinstance(value, float):
                session["pipeline_summary"][key] = round(value, 3)
        session["error_counts"] = dict(session["error_counts"])
    return {"schema_version": 1, "time_filter": {"since_seconds": since, "until_seconds": until},
            "sessions": sessions}


def read_bounded(path: Path, max_bytes: int, max_lines: int):
    with path.open("rb") as source:
        source.seek(0, 2)
        size = source.tell()
        offset = max(0, size - max_bytes)
        source.seek(offset)
        data = source.read(max_bytes)  # One bounded snapshot even while the file grows.
    if offset:
        data = data.split(b"\n", 1)[-1] if b"\n" in data else b""
    # A growing log's incomplete final line must not contribute a partial measurement.
    complete = data.endswith(b"\n")
    lines = data.decode("utf-8", errors="replace").splitlines()
    if not complete and lines:
        lines.pop()
    dropped = max(0, len(lines) - max_lines)
    return lines[-max_lines:], {"bytes_read": len(data), "byte_limit": max_bytes,
                               "line_limit": max_lines, "prefix_truncated": bool(offset or dropped),
                               "incomplete_final_line_ignored": not complete}


def readable(report: dict) -> str:
    output = ["Local stutter report (no raw log lines or input paths)"]
    for number, session in enumerate(report["sessions"], 1):
        work, pacer = session["pipeline_summary"], session["pacer"]
        output.extend([
            f"Session {number}: commit {session['build_sha'] or 'unknown'}, title {session['program_id'] or 'unknown'}",
            f"  Observed seconds: {session['first_observed_seconds']} to {session['last_observed_seconds']}",
            f"  Pipeline summaries: {work['records']} records, {work['builds']} builds, {work['gpu_thread_ms']:.1f} ms GPU-thread work",
            f"  Graphics SPIR-V: {work['graphics_spirv_gpu_thread_ms']:.1f} ms GPU thread / {work['graphics_spirv_worker_ms']:.1f} ms workers; graphics holds {work['graphics_draw_hold_ms']:.1f} ms",
            f"  Largest pacer window interval: {pacer['max_window_interval_ms']} ms; exact frame count >500 ms unavailable",
            f"  Thresholded runtime builds: {json.dumps(session['logged_runtime_builds'], sort_keys=True)}",
            f"  DKB samples: {json.dumps(session['sampled_frame_records'], sort_keys=True)}",
            f"  Error categories: {json.dumps(session['error_counts'], sort_keys=True)}",
        ])
    output.append("Pacer windows, rate-limited DKB samples and pipeline work are distinct metrics; no FPS/causality claim is made.")
    return "\n".join(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--format", choices=("json", "text"), default="text")
    parser.add_argument("--output", type=Path, help="Write a new report file; existing files are never overwritten.")
    parser.add_argument("--max-bytes", type=int, default=16 * 1024 * 1024)
    parser.add_argument("--max-lines", type=int, default=200000)
    parser.add_argument("--since-seconds", type=float, default=0)
    parser.add_argument("--until-seconds", type=float)
    args = parser.parse_args()
    if args.max_bytes <= 0 or args.max_lines <= 0 or args.max_bytes > 256 * 1024 * 1024:
        parser.error("Use positive bounds with max-bytes <= 268435456.")
    if args.since_seconds < 0 or (args.until_seconds is not None and args.until_seconds < args.since_seconds):
        parser.error("Time bounds must be ordered and nonnegative.")
    try:
        lines, bounds = read_bounded(args.input, args.max_bytes, args.max_lines)
        report = analyze(lines, since=args.since_seconds, until=args.until_seconds)
        report["input_bounds"] = bounds
        result = json.dumps(report, indent=2, sort_keys=True) if args.format == "json" else readable(report)
        if args.output:
            with args.output.open("x", encoding="utf-8") as destination:
                destination.write(result + "\n")
        else:
            print(result)
    except OSError:
        parser.exit(1, "Could not read input or create a new report file; check access and output existence.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
