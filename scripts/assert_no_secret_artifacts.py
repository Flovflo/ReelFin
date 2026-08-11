"""Fail if retained QA text contains a configured secret, without echoing it."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path


SECRET_KEYS = (
    "REELFIN_TEST_SERVER_URL", "REELFIN_TEST_USERNAME", "REELFIN_TEST_PASSWORD",
    "JELLYFIN_BASE_URL", "JELLYFIN_USERNAME", "JELLYFIN_PASSWORD",
    "JELLYFIN_SERVER", "JELLYFIN_USER", "JELLYFIN_PASS",
    "REELFIN_SECRET_SCAN_VALUE",
    "TEST_DIRECTPLAY_MP4_ITEM_ID", "TEST_MKV_ITEM_ID", "TEST_HDR_ITEM_ID",
    "TEST_DOLBY_VISION_ITEM_ID",
)


def encoded_secret_pattern(secret: str) -> re.Pattern[str]:
    parts: list[str] = []
    for character in secret:
        encoded_bytes: list[str] = []
        for byte in character.encode("utf-8"):
            high, low = f"{byte:02x}"
            high_pattern = f"[{high.lower()}{high.upper()}]" if high.isalpha() else high
            low_pattern = f"[{low.lower()}{low.upper()}]" if low.isalpha() else low
            encoded_bytes.append(f"%{high_pattern}{low_pattern}")
        parts.append(f"(?:{re.escape(character)}|{''.join(encoded_bytes)})")
    return re.compile("".join(parts), re.IGNORECASE)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact_directory", type=Path)
    parser.add_argument("--secrets-stdin", action="store_true")
    args = parser.parse_args()
    secrets: set[str] = set()
    secrets.update(value for key in SECRET_KEYS if (value := os.environ.get(key)))
    if args.secrets_stdin:
        secrets.update(value for line in sys.stdin for value in [line.rstrip("\r\n")] if value)
    patterns = [encoded_secret_pattern(value) for value in secrets if value]
    forbidden_state = {"DerivedData", "live-ui-target.env"}
    for path in args.artifact_directory.rglob("*"):
        if path.name in forbidden_state or path.suffix == ".xcresult":
            print("Forbidden transient QA state detected in retained artifacts.", file=sys.stderr)
            return 1
        if not path.is_file():
            continue
        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if any(pattern.search(content) for pattern in patterns):
            print("Secret-like value detected in retained QA artifacts.", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
