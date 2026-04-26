#!/usr/bin/env python3
"""Fail ReelFin player E2E when runtime logs contain known broken playback signatures."""

from __future__ import annotations

import argparse
from pathlib import Path


FORBIDDEN_PATTERNS: tuple[tuple[str, str], ...] = (
    ("VRP_RENDER_PIPELINE_FAILURE", "<<<< VRP >>>> signalled err=-12852"),
    ("CAPTION_RENDER_PIPELINE_FAILURE", "<<<< FigCaptionRenderPipeline >>>> signalled err=-12852"),
    ("MAIN_THREAD_CHECKER", "Main Thread Checker: UI API called on a background thread"),
    ("BACKBOARD_THREADING_VIOLATION", "threading violation: expected the main thread"),
    ("CORE_ANIMATION_BACKGROUND_TRANSACTION", "deleted thread with uncommitted CATransaction"),
)


def iter_log_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            files.extend(sorted(path.rglob("*.log")))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan ReelFin player runtime logs for known fatal playback signatures.")
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args()

    findings: list[str] = []
    for log_file in iter_log_files(args.paths):
        try:
            text = log_file.read_text(encoding="utf-8", errors="replace")
        except OSError as error:
            findings.append(f"READ_ERROR {log_file}: {error}")
            continue

        for line_number, line in enumerate(text.splitlines(), start=1):
            for label, pattern in FORBIDDEN_PATTERNS:
                if pattern in line:
                    findings.append(f"{label} {log_file}:{line_number}: {line.strip()}")

    if findings:
        print("FAIL player runtime log cleanliness")
        for finding in findings:
            print(f"  - {finding}")
        return 1

    print("PASS player runtime log cleanliness")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
