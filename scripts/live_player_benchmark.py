#!/usr/bin/env python3
"""Benchmark real Jellyfin original streams used by the ReelFin player."""

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
import time
from dataclasses import asdict, dataclass
from typing import Any, Dict, Optional

import live_directplay_item_probe as probe


@dataclass
class RangeSample:
    offset: int
    status: int
    bytes_read: int
    elapsed_ms: float


@dataclass
class BenchmarkResult:
    label: str
    item_id: str
    container: str
    video_codec: str
    audio_codec: str
    api_contract: str
    supports_direct_play: bool
    content_type: str
    content_length: Optional[int]
    first_byte_ms: float
    range_p50_ms: float
    range_p95_ms: float
    samples: list[RangeSample]
    checks: list[str]
    failures: list[str]


def parse_content_length(headers: Dict[str, str]) -> Optional[int]:
    content_range = headers.get("Content-Range") or headers.get("content-range") or ""
    match = re.search(r"/(\d+)$", content_range)
    if match:
        return int(match.group(1))
    content_length = headers.get("Content-Length") or headers.get("content-length")
    if content_length and content_length.isdigit():
        return int(content_length)
    return None


def timed_range(
    url: str,
    session: probe.Session,
    headers: Dict[str, str],
    offset: int,
    byte_count: int,
) -> tuple[RangeSample, Dict[str, str], bytes]:
    request_headers = dict(headers)
    request_headers["Range"] = f"bytes={offset}-{offset + byte_count - 1}"
    start = time.perf_counter()
    status, response_headers, body = probe.request(
        url,
        token=session.token,
        headers=request_headers,
        timeout=30,
        read_limit=byte_count,
    )
    elapsed_ms = (time.perf_counter() - start) * 1000
    return RangeSample(offset=offset, status=status, bytes_read=len(body), elapsed_ms=elapsed_ms), response_headers, body


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0
    if len(values) == 1:
        return values[0]
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((pct / 100) * (len(ordered) - 1))))
    return ordered[index]


def seek_offsets(content_length: Optional[int]) -> list[int]:
    if not content_length or content_length < 262_144:
        return [0]
    raw_offsets = [
        0,
        int(content_length * 0.10),
        int(content_length * 0.33),
        int(content_length * 0.66),
        int(content_length * 0.90),
    ]
    return sorted(set(max(0, min(content_length - 65_536, offset)) for offset in raw_offsets))


def assert_container_magic(label: str, container: str, body: bytes, failures: list[str], checks: list[str]) -> None:
    lowered = container.lower()
    if any(token in lowered for token in ("mp4", "mov", "m4v")):
        if b"ftyp" in body[:64]:
            checks.append("mp4_ftyp_present")
        else:
            failures.append("mp4_ftyp_missing_in_first_range")
    elif any(token in lowered for token in ("mkv", "matroska")):
        if body.startswith(b"\x1a\x45\xdf\xa3"):
            checks.append("matroska_ebml_header_present")
        else:
            failures.append("matroska_ebml_header_missing")
    else:
        checks.append(f"{label}_container_magic_not_checked")


def expected_api_contract(label: str, container: str) -> str:
    lowered = container.lower()
    if any(token in lowered for token in ("mp4", "mov", "m4v")):
        return "AVPlayerViewController+AVPlayerItem"
    if any(token in lowered for token in ("mkv", "matroska", "webm")):
        return "NativeEngine+AVSampleBufferDisplayLayer"
    return "Unknown"


def benchmark_target(
    server_url: str,
    session: probe.Session,
    target: probe.ProbeTarget,
    range_loops: int,
    byte_count: int,
    max_first_ms: float,
    max_p95_ms: float,
) -> BenchmarkResult:
    info = probe.fetch_playback_info(server_url, session, target.item_id)
    source = probe.selected_source(info, target.item_id)
    url = probe.stream_url(server_url, target.item_id, source, session.token)
    headers = source.get("RequiredHttpHeaders") or {}
    container = str(source.get("Container") or "")
    failures: list[str] = []
    checks: list[str] = []

    first_sample, response_headers, body = timed_range(url, session, headers, 0, byte_count)
    content_type = response_headers.get("Content-Type") or response_headers.get("content-type") or ""
    content_length = parse_content_length(response_headers)

    if first_sample.status not in (200, 206):
        failures.append(f"first_range_http_{first_sample.status}")
    if not body:
        failures.append("first_range_empty")
    if "mpegurl" in content_type.lower() or "m3u8" in content_type.lower():
        failures.append(f"original_stream_returned_hls content_type={content_type}")

    assert_container_magic(target.label, container, body, failures, checks)

    supports_direct_play = bool(source.get("SupportsDirectPlay"))
    api_contract = expected_api_contract(target.label, container)
    if api_contract == "AVPlayerViewController+AVPlayerItem":
        if not supports_direct_play:
            failures.append("apple_native_source_not_marked_direct_play")
        checks.append("apple_native_directplay_contract")
    elif api_contract == "NativeEngine+AVSampleBufferDisplayLayer":
        checks.append("native_samplebuffer_original_contract")

    if target.require_hdr and not probe.has_hdr_metadata(source):
        failures.append("missing_hdr_metadata")
    elif target.require_hdr:
        checks.append("hdr_metadata_present")
    if target.require_dolby_vision and not probe.has_dolby_vision_metadata(source):
        failures.append("missing_dolby_vision_metadata")
    elif target.require_dolby_vision:
        checks.append("dolby_vision_metadata_present")

    samples = [first_sample]
    for _ in range(range_loops):
        for offset in seek_offsets(content_length):
            sample, _, _ = timed_range(url, session, headers, offset, byte_count)
            samples.append(sample)
            if sample.status not in (200, 206):
                failures.append(f"seek_http_{sample.status}@{offset}")
            if sample.bytes_read == 0:
                failures.append(f"seek_empty@{offset}")

    elapsed = [sample.elapsed_ms for sample in samples]
    range_p50 = statistics.median(elapsed)
    range_p95 = percentile(elapsed, 95)
    if first_sample.elapsed_ms > max_first_ms:
        failures.append(f"first_range_slow_{first_sample.elapsed_ms:.1f}ms")
    if range_p95 > max_p95_ms:
        failures.append(f"seek_p95_slow_{range_p95:.1f}ms")

    return BenchmarkResult(
        label=target.label,
        item_id=target.item_id[:8],
        container=container or "unknown",
        video_codec=str(source.get("VideoCodec") or "unknown"),
        audio_codec=str(source.get("AudioCodec") or "unknown"),
        api_contract=api_contract,
        supports_direct_play=supports_direct_play,
        content_type=content_type or "unknown",
        content_length=content_length,
        first_byte_ms=first_sample.elapsed_ms,
        range_p50_ms=range_p50,
        range_p95_ms=range_p95,
        samples=samples,
        checks=checks,
        failures=sorted(set(failures)),
    )


def print_result(result: BenchmarkResult) -> None:
    status = "PASS" if not result.failures else "FAIL"
    size = result.content_length if result.content_length is not None else "unknown"
    print(
        f"{status} {result.label} item={result.item_id} api={result.api_contract} "
        f"container={result.container} video={result.video_codec} audio={result.audio_codec} "
        f"size={size} first={result.first_byte_ms:.1f}ms "
        f"p50={result.range_p50_ms:.1f}ms p95={result.range_p95_ms:.1f}ms "
        f"samples={len(result.samples)} checks={','.join(result.checks) or 'none'}"
    )
    for failure in result.failures:
        print(f"  - {failure}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark ReelFin live player original stream access.")
    parser.add_argument("--range-loops", type=int, default=3)
    parser.add_argument("--range-bytes", type=int, default=65_536)
    parser.add_argument("--max-first-ms", type=float, default=5000)
    parser.add_argument("--max-p95-ms", type=float, default=5000)
    parser.add_argument("--json-out")
    args = parser.parse_args()

    try:
        server_url, username, password = probe.validate_environment()
        session = probe.authenticate(server_url, username, password)
        print(f"Authenticated as '{username}'. Benchmarking explicit original streams.")
        results = [
            benchmark_target(
                server_url=server_url,
                session=session,
                target=target,
                range_loops=max(1, args.range_loops),
                byte_count=max(4096, args.range_bytes),
                max_first_ms=args.max_first_ms,
                max_p95_ms=args.max_p95_ms,
            )
            for target in probe.configured_targets()
        ]
    except probe.ProbeFailure as error:
        print(f"Benchmark error: {error}")
        return 2

    for result in results:
        print_result(result)

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as handle:
            json.dump([asdict(result) for result in results], handle, indent=2)

    failures = sum(1 for result in results if result.failures)
    print(f"Summary: {len(results) - failures}/{len(results)} benchmark targets passed.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
