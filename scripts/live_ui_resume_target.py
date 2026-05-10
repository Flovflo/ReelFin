#!/usr/bin/env python3
"""Prepare and restore a Jellyfin resume row for live UI player targeting."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

import live_directplay_item_probe as probe
import live_resume_reporting_probe as resume_probe


def env_value(*names: str) -> str:
    for name in names:
        value = os.environ.get(name, "")
        if value and value != "...":
            return value
    return ""


def load_session() -> tuple[str, probe.Session]:
    server_url = env_value("JELLYFIN_BASE_URL", "REELFIN_TEST_SERVER_URL")
    username = env_value("JELLYFIN_USERNAME", "REELFIN_TEST_USERNAME")
    password = env_value("JELLYFIN_PASSWORD", "REELFIN_TEST_PASSWORD")
    missing = [
        name
        for name, value in (
            ("JELLYFIN_BASE_URL/REELFIN_TEST_SERVER_URL", server_url),
            ("JELLYFIN_USERNAME/REELFIN_TEST_USERNAME", username),
            ("JELLYFIN_PASSWORD/REELFIN_TEST_PASSWORD", password),
        )
        if not value
    ]
    if missing:
        raise probe.ProbeFailure("missing_env=" + ",".join(missing))
    return server_url, probe.authenticate(server_url, username, password)


def prepare(item_id: str, state_file: Path) -> None:
    server_url, session = load_session()
    normalized_item_id = probe.normalized_item_id(item_id)
    item = resume_probe.fetch_item(server_url, session, normalized_item_id)
    original_ticks = resume_probe.playback_position_ticks(item)
    target_ticks = resume_probe.choose_probe_ticks(item)

    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(
        json.dumps(
            {
                "item_id": normalized_item_id,
                "original_ticks": original_ticks,
                "target_ticks": target_ticks,
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )

    resume_probe.report_stopped_position(server_url, session, normalized_item_id, target_ticks)
    time.sleep(1.0)
    verified_item = resume_probe.fetch_item(server_url, session, normalized_item_id)
    actual_ticks = resume_probe.playback_position_ticks(verified_item)
    delta = abs(actual_ticks - target_ticks)
    if delta > resume_probe.VERIFY_TOLERANCE_TICKS:
        raise probe.ProbeFailure(
            f"ui_resume_prepare_mismatch expected={target_ticks} actual={actual_ticks} delta={delta}"
        )
    print(
        "PASS ui_resume_prepare "
        f"item={normalized_item_id[:8]} "
        f"targetSeconds={target_ticks / resume_probe.TICKS_PER_SECOND:.3f} "
        f"originalSeconds={original_ticks / resume_probe.TICKS_PER_SECOND:.3f}"
    )


def restore(state_file: Path) -> None:
    if not state_file.exists():
        print(f"WARN ui_resume_restore_skipped reason=missing_state_file")
        return

    state: dict[str, Any] = json.loads(state_file.read_text(encoding="utf-8"))
    item_id = str(state["item_id"])
    original_ticks = int(state["original_ticks"])
    server_url, session = load_session()
    resume_probe.report_stopped_position(server_url, session, item_id, original_ticks)
    print(
        "PASS ui_resume_restore "
        f"item={item_id[:8]} "
        f"restoredSeconds={original_ticks / resume_probe.TICKS_PER_SECOND:.3f}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--item-id", required=True)
    prepare_parser.add_argument("--state-file", required=True)

    restore_parser = subparsers.add_parser("restore")
    restore_parser.add_argument("--state-file", required=True)

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "prepare":
            prepare(args.item_id, Path(args.state_file))
        else:
            restore(Path(args.state_file))
        return 0
    except probe.ProbeFailure as error:
        print(f"Probe error: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
