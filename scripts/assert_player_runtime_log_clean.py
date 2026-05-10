#!/usr/bin/env python3
"""Fail ReelFin player E2E when runtime logs contain known broken playback signatures."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


FORBIDDEN_PATTERNS: tuple[tuple[str, str], ...] = (
    ("VRP_RENDER_PIPELINE_FAILURE", "<<<< VRP >>>> signalled err=-12852"),
    ("CAPTION_RENDER_PIPELINE_FAILURE", "<<<< FigCaptionRenderPipeline >>>> signalled err=-12852"),
    ("MAIN_THREAD_CHECKER", "Main Thread Checker: UI API called on a background thread"),
    ("BACKBOARD_THREADING_VIOLATION", "threading violation: expected the main thread"),
    ("CORE_ANIMATION_BACKGROUND_TRANSACTION", "deleted thread with uncommitted CATransaction"),
    ("PLAYBACK_STALL", "MEDIA_PLAYBACK_STALL"),
    ("PLAYBACK_STALLED", "Playback stalled."),
    ("STARTUP_READINESS_TIMEOUT", "playback.startup.readiness.timeout"),
    ("IOS_HLS_STARTUP_GATE", "ios_high_bitrate_hls"),
    ("DIRECTPLAY_RANGE_TIMEOUT", "directplay_range_deep error=The request timed out"),
    ("DIRECTPLAY_RANGE_TIMEOUT", "directplay_range_deep error=The operation couldn’t be completed. (NSURLErrorDomain error -1001.)"),
    ("URL_TIMEOUT", "NSURLErrorDomain Code=-1001"),
    ("LOCAL_GATEWAY_LOOPBACK_FAILURE", "NSErrorFailingURLStringKey=http://127.0.0.1"),
    ("LOCAL_GATEWAY_WRAP_PREVENTED", "playback.cache.gateway.wrap_prevented"),
    ("LEGACY_NATIVEPLAYER_BRANCH_LOG", "branch=feature/native-swift-player"),
)

FORBIDDEN_REGEXES: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "RAW_API_KEY_URL",
        re.compile(r"(?i)\bapi_key=(?!(?:REDACTED|<redacted>|%3Credacted%3E)(?:\b|&))[^&\s]+"),
    ),
    (
        "RAW_PASSWORD_ACCESSIBILITY_VALUE",
        re.compile(r"\btext = '(?!<redacted>)[^']+' \(length = \d+\).*placeholder = Password"),
    ),
)

FORBIDDEN_TEXT_REGEXES: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "LOCAL_GATEWAY_CONNECTION_REFUSED",
        re.compile(r"(?is)(?:127\.0\.0\.1|localhost).{0,500}connection refused|connection refused.{0,500}(?:127\.0\.0\.1|localhost)"),
    ),
    (
        "DIRECTPLAY_RECOVERY_RELOADED_LOCAL_GATEWAY",
        re.compile(r"(?im)^.*playback\.directplay\.recovery_reloaded\b.*\burl=http://(?:127\.0\.0\.1|localhost)\b.*$"),
    ),
)


@dataclass(frozen=True)
class LogContext:
    ignores_ios_simulator_hdr_dv_render_noise: bool


def session_id(line: str) -> str | None:
    match = re.search(r"\bsession=([^\s]+)", line)
    return match.group(1) if match else None


def build_log_context(path: Path, text: str) -> LogContext:
    if path.name != "ios-live-ui-runtime.stream":
        return LogContext(ignores_ios_simulator_hdr_dv_render_noise=False)

    hdr_dv_proofs: set[str] = set()
    first_frames: set[str] = set()
    ttffs: set[str] = set()
    for line in text.splitlines():
        current_session = session_id(line)
        if current_session is None:
            continue
        if "playback.proof" in line and ("dv=true" in line or "hdr=PQ" in line or "hdr=HLG" in line):
            hdr_dv_proofs.add(current_session)
        elif "avplayer.first-frame" in line:
            first_frames.add(current_session)
        elif "playback.ttff" in line:
            ttffs.add(current_session)

    successful_hdr_dv_sessions = hdr_dv_proofs & first_frames & ttffs
    return LogContext(ignores_ios_simulator_hdr_dv_render_noise=bool(successful_hdr_dv_sessions))


def is_ignorable_line(label: str, line: str, context: LogContext) -> bool:
    if label in {"VRP_RENDER_PIPELINE_FAILURE", "CAPTION_RENDER_PIPELINE_FAILURE"}:
        if "xctest[" in line or "ReelFinUITests-Runner[" in line:
            return True
        if context.ignores_ios_simulator_hdr_dv_render_noise and "ReelFin[" in line:
            return True
    return False


def redact_sensitive(text: str) -> str:
    text = re.sub(
        r"(?i)\bapi_key=(?!(?:REDACTED|<redacted>|%3Credacted%3E)(?:\b|&))[^&\s]+",
        "api_key=<redacted>",
        text,
    )
    if "placeholder = Password" in text:
        text = re.sub(
            r"text = '[^']+' \(length = \d+\)",
            "text = '<redacted>' (length = <redacted>)",
            text,
        )
    return re.sub(r"https?://\S+", "<redacted-url>", text)


def iter_log_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            files.extend(sorted(path.rglob("*.log")))
            files.extend(sorted(path.rglob("*.stream")))
    return [file for file in files if not file.name.startswith("runtime-log-cleanliness")]


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

        context = build_log_context(log_file, text)
        for line_number, line in enumerate(text.splitlines(), start=1):
            for label, pattern in FORBIDDEN_PATTERNS:
                if pattern in line:
                    if is_ignorable_line(label, line, context):
                        continue
                    findings.append(f"{label} {log_file}:{line_number}: {redact_sensitive(line.strip())}")
            for label, pattern in FORBIDDEN_REGEXES:
                if pattern.search(line):
                    if is_ignorable_line(label, line, context):
                        continue
                    findings.append(f"{label} {log_file}:{line_number}: {redact_sensitive(line.strip())}")

        for label, pattern in FORBIDDEN_TEXT_REGEXES:
            for match in pattern.finditer(text):
                line_number = text.count("\n", 0, match.start()) + 1
                snippet = " ".join(match.group(0).split())
                findings.append(f"{label} {log_file}:{line_number}: {redact_sensitive(snippet)}")

    if findings:
        print("FAIL player runtime log cleanliness")
        for finding in findings:
            print(f"  - {finding}")
        return 1

    print("PASS player runtime log cleanliness")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
