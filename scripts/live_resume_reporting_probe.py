#!/usr/bin/env python3
"""Verify Jellyfin persists resume position after Playback Stopped."""

from __future__ import annotations

import os
import sys
import time
from typing import Any

import live_directplay_item_probe as probe


TICKS_PER_SECOND = 10_000_000
VERIFY_TOLERANCE_TICKS = 2 * TICKS_PER_SECOND


def fetch_item(server_url: str, session: probe.Session, item_id: str) -> dict[str, Any]:
    status, _, payload = probe.request(
        f"{server_url.rstrip('/')}/Users/{session.user_id}/Items/{item_id}",
        token=session.token,
        headers={"Accept": "application/json"},
    )
    if status != 200:
        raise probe.ProbeFailure(f"item_http_{status}")
    return probe.decode_json(payload, "item")


def playback_position_ticks(item: dict[str, Any]) -> int:
    user_data = item.get("UserData") or {}
    value = user_data.get("PlaybackPositionTicks") or 0
    return int(value)


def choose_probe_ticks(item: dict[str, Any]) -> int:
    configured_seconds = os.environ.get("REELFIN_RESUME_PROBE_SECONDS")
    if configured_seconds:
        return max(0, int(float(configured_seconds) * TICKS_PER_SECOND))

    runtime_ticks = int(item.get("RunTimeTicks") or 0)
    if runtime_ticks <= 0:
        return 120 * TICKS_PER_SECOND

    runtime_seconds = runtime_ticks / TICKS_PER_SECOND
    if runtime_seconds > 900:
        target_seconds = 549.35
    elif runtime_seconds > 180:
        target_seconds = min(120, runtime_seconds * 0.5)
    else:
        target_seconds = max(10, runtime_seconds * 0.25)

    if runtime_seconds > 60:
        target_seconds = min(target_seconds, runtime_seconds - 45)
    return max(0, int(target_seconds * TICKS_PER_SECOND))


def post_progress(server_url: str, session: probe.Session, item_id: str, ticks: int, endpoint: str) -> None:
    body = {
        "ItemId": item_id,
        "PositionTicks": ticks,
        "CanSeek": True,
        "IsPaused": True,
        "IsMuted": False,
        "PlayMethod": "DirectPlay",
    }
    status, _, payload = probe.request(
        f"{server_url.rstrip('/')}/Sessions/Playing/{endpoint}",
        method="POST",
        token=session.token,
        headers={"Accept": "application/json"},
        body=body,
    )
    if status not in (200, 204):
        detail = payload.decode("utf-8", "replace")[:160]
        raise probe.ProbeFailure(f"{endpoint.lower()}_http_{status} {detail}")


def report_stopped_position(server_url: str, session: probe.Session, item_id: str, ticks: int) -> None:
    post_progress(server_url, session, item_id, ticks, "Progress")
    post_progress(server_url, session, item_id, ticks, "Stopped")


def validate_environment() -> tuple[str, str, str, str]:
    server_url = os.environ.get("JELLYFIN_BASE_URL") or os.environ.get("REELFIN_TEST_SERVER_URL") or ""
    username = os.environ.get("JELLYFIN_USERNAME") or os.environ.get("REELFIN_TEST_USERNAME") or ""
    password = os.environ.get("JELLYFIN_PASSWORD") or os.environ.get("REELFIN_TEST_PASSWORD") or ""
    item_id = probe.normalized_item_id(os.environ.get("TEST_DIRECTPLAY_MP4_ITEM_ID", ""))
    missing = [
        name
        for name, value in (
            ("JELLYFIN_BASE_URL", server_url),
            ("JELLYFIN_USERNAME", username),
            ("JELLYFIN_PASSWORD", password),
            ("TEST_DIRECTPLAY_MP4_ITEM_ID", item_id),
        )
        if not value or value == "..."
    ]
    if missing:
        raise probe.ProbeFailure("missing_env=" + ",".join(missing))
    return server_url, username, password, item_id


def main() -> int:
    try:
        server_url, username, password, item_id = validate_environment()
        session = probe.authenticate(server_url, username, password)
        item = fetch_item(server_url, session, item_id)
        original_ticks = playback_position_ticks(item)
        target_ticks = choose_probe_ticks(item)

        try:
            report_stopped_position(server_url, session, item_id, target_ticks)
            time.sleep(1.0)
            verified_item = fetch_item(server_url, session, item_id)
            actual_ticks = playback_position_ticks(verified_item)
            delta = abs(actual_ticks - target_ticks)
            if delta > VERIFY_TOLERANCE_TICKS:
                raise probe.ProbeFailure(
                    f"resume_position_mismatch expected={target_ticks} actual={actual_ticks} delta={delta}"
                )
            print(
                "PASS resume_reporting "
                f"item={item_id[:8]} user={username} "
                f"targetSeconds={target_ticks / TICKS_PER_SECOND:.3f} "
                f"actualSeconds={actual_ticks / TICKS_PER_SECOND:.3f}"
            )
            return 0
        finally:
            if original_ticks != target_ticks:
                try:
                    report_stopped_position(server_url, session, item_id, original_ticks)
                except probe.ProbeFailure as restore_error:
                    print(f"WARN resume_restore_failed item={item_id[:8]} reason={restore_error}")
    except probe.ProbeFailure as error:
        print(f"Probe error: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
