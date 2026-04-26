#!/usr/bin/env python3
"""
Live Jellyfin playback probe loop.

This script validates the same critical path as the iOS playback coordinator:
- authenticate
- resolve candidate items
- build transcode playback URL (server default + conservative profile)
- probe master playlist, variant playlist, and first segment

Exit code is non-zero when failures exceed the configured budget.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Tuple
from urllib.error import HTTPError


USER_AGENT = "ReelFin/1.0"
MAX_STREAMING_BITRATE = 120_000_000


@dataclass
class Session:
    user_id: str
    token: str


@dataclass
class ProbeCandidate:
    item_id: str
    name: str
    source_id: str
    video_codec: Optional[str]
    transcoding_url: Optional[str]
    required_headers: Dict[str, str]


class ProbeError(Exception):
    pass


def normalized_item_id(raw: str) -> str:
    value = raw.strip()
    uuid_match = re.search(
        r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b",
        value,
    )
    if uuid_match:
        return uuid_match.group(0)
    hex_match = re.search(r"\b[0-9a-fA-F]{32}\b", value)
    if hex_match:
        return hex_match.group(0)
    return value


def emby_authorization(token: Optional[str]) -> str:
    parts = [
        'Client="ReelFin"',
        'Device="iOS"',
        'DeviceId="live-probe"',
        'Version="1.0"',
    ]
    if token:
        parts.append(f'Token="{token}"')
    return "MediaBrowser " + ", ".join(parts)


def request(
    url: str,
    method: str = "GET",
    token: Optional[str] = None,
    headers: Optional[Dict[str, str]] = None,
    body: Optional[dict] = None,
    timeout: int = 20,
) -> Tuple[int, Dict[str, str], bytes]:
    request_headers = {
        "User-Agent": USER_AGENT,
        "X-Emby-Authorization": emby_authorization(token),
    }
    if token:
        request_headers["X-Emby-Token"] = token
    if headers:
        request_headers.update(headers)

    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        request_headers["Content-Type"] = "application/json"

    req = urllib.request.Request(url, method=method, headers=request_headers, data=data)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, dict(response.getheaders()), response.read()
    except HTTPError as error:
        return error.code, dict(error.headers.items()), error.read()


def absolute_url(server_url: str, maybe_relative: str) -> str:
    if maybe_relative.startswith("http://") or maybe_relative.startswith("https://"):
        return maybe_relative
    return urllib.parse.urljoin(server_url.rstrip("/") + "/", maybe_relative.lstrip("/"))


def parse_first_media_line(manifest: str) -> Optional[str]:
    for raw in manifest.splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            return line
    return None


def normalized_video_codec(codec: Optional[str]) -> Optional[str]:
    if not codec:
        return None
    lowered = codec.lower()
    if any(token in lowered for token in ("hevc", "h265", "dvhe", "dvh1")):
        return "hevc"
    if any(token in lowered for token in ("h264", "avc1")):
        return "h264"
    return None


def ensure_api_key(url: str, token: str) -> str:
    parts = urllib.parse.urlsplit(url)
    query = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    if not any(key.lower() == "api_key" for key, _ in query):
        query.append(("api_key", token))
    return urllib.parse.urlunsplit(
        (
            parts.scheme,
            parts.netloc,
            parts.path,
            urllib.parse.urlencode(query),
            parts.fragment,
        )
    )


def conservative_transcode_url(url: str, max_bitrate: int, video_codec: Optional[str]) -> str:
    parts = urllib.parse.urlsplit(url)
    query_items = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    query_map: Dict[str, str] = {key: value for key, value in query_items}

    preferred_video = normalized_video_codec(video_codec)
    if preferred_video:
        query_map["VideoCodec"] = preferred_video
    elif "VideoCodec" in query_map:
        del query_map["VideoCodec"]

    query_map["AudioCodec"] = "aac"
    query_map["Container"] = "ts"
    query_map["SegmentContainer"] = "ts"
    query_map["AllowVideoStreamCopy"] = "true"
    query_map["AllowAudioStreamCopy"] = "false"
    query_map["MaxStreamingBitrate"] = str(max_bitrate)
    query_map["BreakOnNonKeyFrames"] = "True"
    query_map["TranscodeReasons"] = "ContainerNotSupported,AudioCodecNotSupported"

    query = urllib.parse.urlencode(sorted(query_map.items(), key=lambda item: item[0]))
    return urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path, query, parts.fragment))


def build_fallback_master_url(server_url: str, item_id: str, source_id: str, token: str, video_codec: Optional[str]) -> str:
    query: Dict[str, str] = {
        "AudioCodec": "aac",
        "Container": "ts",
        "SegmentContainer": "ts",
        "AllowVideoStreamCopy": "true",
        "AllowAudioStreamCopy": "false",
        "MaxStreamingBitrate": str(MAX_STREAMING_BITRATE),
        "MediaSourceId": source_id,
        "TranscodeReasons": "ContainerNotSupported,AudioCodecNotSupported",
        "api_key": token,
    }
    preferred_video = normalized_video_codec(video_codec)
    if preferred_video:
        query["VideoCodec"] = preferred_video
    return f"{server_url.rstrip('/')}/Videos/{item_id}/master.m3u8?{urllib.parse.urlencode(query)}"


def decode_json_or_raise(payload: bytes, context: str) -> dict:
    try:
        return json.loads(payload.decode("utf-8"))
    except Exception as error:  # noqa: BLE001
        raise ProbeError(f"{context}: invalid JSON response: {error}") from error


def authenticate(server_url: str, username: str, password: str) -> Session:
    status, _, body = request(
        f"{server_url.rstrip('/')}/Users/AuthenticateByName",
        method="POST",
        headers={"Accept": "application/json"},
        body={"Username": username, "Pw": password},
    )
    if status != 200:
        raise ProbeError(f"Authentication failed (HTTP {status}).")
    payload = decode_json_or_raise(body, "authenticate")
    return Session(user_id=payload["User"]["Id"], token=payload["AccessToken"])


def fetch_items(server_url: str, session: Session, limit: int) -> List[dict]:
    collected: List[dict] = []
    seen: set[str] = set()
    endpoints = [
        f"{server_url.rstrip('/')}/Users/{session.user_id}/Items/Resume?Limit={max(5, limit)}",
        f"{server_url.rstrip('/')}/Users/{session.user_id}/Items?Recursive=true&Limit={max(20, limit * 2)}&SortBy=DateCreated&SortOrder=Descending",
    ]

    for endpoint in endpoints:
        status, _, body = request(endpoint, token=session.token, headers={"Accept": "application/json"})
        if status != 200:
            continue
        payload = decode_json_or_raise(body, "fetch_items")
        for item in payload.get("Items", []):
            item_id = item.get("Id")
            if not item_id or item_id in seen:
                continue
            seen.add(item_id)
            collected.append(item)
            if len(collected) >= limit:
                return collected
    return collected


def fetch_candidate(server_url: str, session: Session, item: dict) -> Optional[ProbeCandidate]:
    item_id = item.get("Id")
    if not item_id:
        return None

    body = {
        "UserId": session.user_id,
        "EnableDirectPlay": True,
        "EnableDirectStream": True,
        "EnableTranscoding": True,
        "MaxStreamingBitrate": MAX_STREAMING_BITRATE,
    }
    status, _, payload = request(
        f"{server_url.rstrip('/')}/Items/{item_id}/PlaybackInfo",
        method="POST",
        token=session.token,
        headers={"Accept": "application/json"},
        body=body,
    )
    if status != 200:
        return None

    response = decode_json_or_raise(payload, "fetch_candidate")
    media_sources: List[dict] = response.get("MediaSources", [])
    if not media_sources:
        return None

    source = media_sources[0]
    media_streams: List[dict] = source.get("MediaStreams", [])
    first_video = next((stream for stream in media_streams if (stream.get("Type") or "").lower() == "video"), None)

    return ProbeCandidate(
        item_id=item_id,
        name=item.get("Name") or item_id,
        source_id=source.get("Id") or item_id,
        video_codec=source.get("VideoCodec") or (first_video or {}).get("Codec"),
        transcoding_url=source.get("TranscodingUrl"),
        required_headers=source.get("RequiredHttpHeaders") or {},
    )


def probe_hls(master_url: str, token: str, required_headers: Dict[str, str]) -> Tuple[bool, str]:
    headers = {
        "Accept": "application/vnd.apple.mpegurl,application/x-mpegURL,*/*",
        **required_headers,
    }

    master_status, _, master_body = request(master_url, token=token, headers=headers)
    if master_status != 200:
        return False, f"master_http_{master_status}"

    try:
        master_text = master_body.decode("utf-8")
    except UnicodeDecodeError:
        return False, "master_decode_failed"
    if "#EXTM3U" not in master_text:
        return False, "master_not_hls"

    first = parse_first_media_line(master_text)
    if not first:
        return False, "master_no_media_line"
    child_url = urllib.parse.urljoin(master_url, first)

    target_url = child_url
    if child_url.lower().endswith(".m3u8") or ".m3u8?" in child_url.lower():
        child_status, _, child_body = request(child_url, token=token, headers=headers)
        if child_status != 200:
            return False, f"child_http_{child_status}"
        child_text = child_body.decode("utf-8", "replace")
        if "#EXTM3U" not in child_text:
            return False, "child_not_hls"
        first_segment = parse_first_media_line(child_text)
        if not first_segment:
            return False, "child_no_segment_line"
        target_url = urllib.parse.urljoin(child_url, first_segment)

    segment_headers = dict(required_headers)
    segment_headers["Range"] = "bytes=0-2047"
    segment_status, _, _ = request(target_url, token=token, headers=segment_headers)
    if segment_status not in (200, 206):
        return False, f"segment_http_{segment_status}"
    return True, "ok"


def iterate_candidates(server_url: str, session: Session, sample_size: int) -> Iterable[ProbeCandidate]:
    seen: set[str] = set()
    for item in explicit_probe_items():
        item_id = item["Id"]
        if item_id in seen:
            continue
        seen.add(item_id)
        candidate = fetch_candidate(server_url, session, item)
        if candidate:
            yield candidate

    items = fetch_items(server_url, session, sample_size)
    for item in items:
        item_id = item.get("Id")
        if item_id in seen:
            continue
        if item_id:
            seen.add(item_id)
        candidate = fetch_candidate(server_url, session, item)
        if candidate:
            yield candidate


def explicit_probe_items() -> list[dict]:
    values = [
        ("directplay_mp4", os.environ.get("TEST_DIRECTPLAY_MP4_ITEM_ID", "")),
        ("mkv_original", os.environ.get("TEST_MKV_ITEM_ID", "") or os.environ.get("TEST_MKV_DOLBY_VISION_ITEM_ID", "")),
        (
            "dolby_vision_original",
            os.environ.get("TEST_DOLBY_VISION_ITEM_ID", "")
            or os.environ.get("TEST_DIRECTPLAY_DOLBY_VISION_ITEM_ID", "")
            or os.environ.get("TEST_MKV_DOLBY_VISION_ITEM_ID", ""),
        ),
    ]
    items: list[dict] = []
    for name, raw in values:
        if not raw or raw == "...":
            continue
        item_id = normalized_item_id(raw)
        if item_id and item_id != "...":
            items.append({"Id": item_id, "Name": name})
    return items


def run_loop(
    server_url: str,
    username: str,
    password: str,
    loops: int,
    sample_size: int,
    max_failures: int,
) -> int:
    session = authenticate(server_url, username, password)
    total = 0
    failures = 0

    print(f"Authenticated as '{username}'. Running {loops} loop(s), sample={sample_size}.")

    for loop_index in range(1, loops + 1):
        print(f"\n=== LIVE LOOP {loop_index}/{loops} ===")
        candidates = list(iterate_candidates(server_url, session, sample_size))
        if not candidates:
            print("No playable items found for probe.")
            failures += 1
            continue

        for candidate in candidates:
            total += 1
            master_url: str
            if candidate.transcoding_url:
                master_url = ensure_api_key(absolute_url(server_url, candidate.transcoding_url), session.token)
            else:
                master_url = build_fallback_master_url(
                    server_url,
                    item_id=candidate.item_id,
                    source_id=candidate.source_id,
                    token=session.token,
                    video_codec=candidate.video_codec,
                )

            ok_default, reason_default = probe_hls(master_url, session.token, candidate.required_headers)
            if ok_default:
                print(f"PASS default      | {candidate.name}")
                continue

            conservative_url = conservative_transcode_url(master_url, MAX_STREAMING_BITRATE, candidate.video_codec)
            ok_conservative, reason_conservative = probe_hls(conservative_url, session.token, candidate.required_headers)
            if ok_conservative:
                print(f"PASS conservative | {candidate.name} ({reason_default} -> ok)")
            else:
                failures += 1
                print(
                    f"FAIL               | {candidate.name} "
                    f"(default={reason_default}, conservative={reason_conservative})"
                )

    passed = max(0, total - failures)
    print(f"\nSummary: {passed}/{total} passed, {failures} failed (budget: {max_failures}).")

    return 0 if failures <= max_failures else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Run live Jellyfin playback probes.")
    parser.add_argument("--loops", type=int, default=int(os.environ.get("REELFIN_TEST_LOOPS", "2")))
    parser.add_argument("--sample-size", type=int, default=int(os.environ.get("REELFIN_TEST_SAMPLE_SIZE", "8")))
    parser.add_argument("--max-failures", type=int, default=int(os.environ.get("REELFIN_TEST_MAX_FAILURES", "0")))
    args = parser.parse_args()

    server_url = os.environ.get("REELFIN_TEST_SERVER_URL")
    username = os.environ.get("REELFIN_TEST_USERNAME")
    password = os.environ.get("REELFIN_TEST_PASSWORD")

    if not server_url or not username or not password:
        print("Missing REELFIN_TEST_SERVER_URL / REELFIN_TEST_USERNAME / REELFIN_TEST_PASSWORD.")
        return 2

    loops = max(1, args.loops)
    sample_size = max(1, args.sample_size)
    max_failures = max(0, args.max_failures)

    try:
        return run_loop(
            server_url=server_url,
            username=username,
            password=password,
            loops=loops,
            sample_size=sample_size,
            max_failures=max_failures,
        )
    except ProbeError as error:
        print(f"Probe error: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
