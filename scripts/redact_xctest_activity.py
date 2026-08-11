"""Remove configured secrets and arbitrary percent-encoded forms from QA output."""

from __future__ import annotations

import os
import re
import sys


SECRET_KEYS = (
    "REELFIN_TEST_SERVER_URL", "REELFIN_TEST_USERNAME", "REELFIN_TEST_PASSWORD",
    "JELLYFIN_BASE_URL", "JELLYFIN_USERNAME", "JELLYFIN_PASSWORD",
    "JELLYFIN_SERVER", "JELLYFIN_USER", "JELLYFIN_PASS",
    "REELFIN_SECRET_SCAN_VALUE",
    "TEST_DIRECTPLAY_MP4_ITEM_ID", "TEST_MKV_ITEM_ID", "TEST_HDR_ITEM_ID",
    "TEST_DOLBY_VISION_ITEM_ID",
)


def secret_values() -> list[str]:
    values = [value for key in SECRET_KEYS if (value := os.environ.get(key))]
    # Longest first prevents a URL from leaving its query-string secret behind.
    return sorted(set(values), key=len, reverse=True)


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


def redact(text: str, secrets: list[str]) -> str:
    for secret in secrets:
        text = encoded_secret_pattern(secret).sub("<redacted>", text)
    return text


def main() -> int:
    secrets = secret_values()
    for line in sys.stdin:
        sys.stdout.write(redact(line, secrets))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
