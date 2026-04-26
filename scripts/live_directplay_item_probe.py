#!/usr/bin/env python3
"""Probe explicit Jellyfin items used to validate ReelFin playback routes."""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Dict, Iterable, Optional, Tuple
from urllib.error import HTTPError, URLError


USER_AGENT = "ReelFin/1.0 PlayerE2E"
MAX_STREAMING_BITRATE = 120_000_000


@dataclass
class Session:
    user_id: str
    token: str


@dataclass
class ProbeTarget:
    label: str
    item_id: str
    required_container_tokens: tuple[str, ...] = ()
    require_server_direct_play: bool = False
    require_hdr: bool = False
    require_dolby_vision: bool = False


class ProbeFailure(Exception):
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
        'Device="PlayerE2E"',
        'DeviceId="reelfin-player-e2e"',
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
    timeout: int = 25,
    read_limit: Optional[int] = None,
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
        request_headers["Accept"] = "application/json"

    req = urllib.request.Request(url, method=method, headers=request_headers, data=data)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            payload = response.read(read_limit) if read_limit is not None else response.read()
            return response.status, dict(response.getheaders()), payload
    except HTTPError as error:
        return error.code, dict(error.headers.items()), error.read()
    except URLError as error:
        raise ProbeFailure(f"network_error={error.reason}") from error


def decode_json(payload: bytes, context: str) -> dict:
    try:
        return json.loads(payload.decode("utf-8"))
    except Exception as error:  # noqa: BLE001
        raise ProbeFailure(f"{context}: invalid JSON: {error}") from error


def authenticate(server_url: str, username: str, password: str) -> Session:
    status, _, body = request(
        f"{server_url.rstrip('/')}/Users/AuthenticateByName",
        method="POST",
        headers={"Accept": "application/json"},
        body={"Username": username, "Pw": password},
    )
    if status != 200:
        raise ProbeFailure(f"authentication_http_{status}")
    payload = decode_json(body, "authenticate")
    return Session(user_id=payload["User"]["Id"], token=payload["AccessToken"])


def fetch_playback_info(server_url: str, session: Session, item_id: str) -> dict:
    body = {
        "UserId": session.user_id,
        "EnableDirectPlay": True,
        "EnableDirectStream": True,
        "EnableTranscoding": True,
        "MaxStreamingBitrate": MAX_STREAMING_BITRATE,
        "AllowVideoStreamCopy": True,
        "AllowAudioStreamCopy": True,
    }
    status, _, payload = request(
        f"{server_url.rstrip('/')}/Items/{item_id}/PlaybackInfo",
        method="POST",
        token=session.token,
        headers={"Accept": "application/json"},
        body=body,
    )
    if status != 200:
        raise ProbeFailure(f"playback_info_http_{status}")
    return decode_json(payload, "playback_info")


def selected_source(info: dict, item_id: str) -> dict:
    sources = info.get("MediaSources") or []
    if not sources:
        raise ProbeFailure("no_media_sources")
    exact = next((source for source in sources if source.get("Id") == item_id), None)
    return exact or sources[0]


def stream_url(server_url: str, item_id: str, source: dict, token: str) -> str:
    extension = preferred_static_stream_extension(source)
    stream_leaf = f"stream.{extension}" if extension else "stream"
    query = urllib.parse.urlencode(
        {
            "static": "true",
            "MediaSourceId": source.get("Id") or item_id,
            "api_key": token,
        }
    )
    return f"{server_url.rstrip('/')}/Videos/{item_id}/{stream_leaf}?{query}"


def preferred_static_stream_extension(source: dict) -> Optional[str]:
    supported = {"mp4", "m4v", "mov"}
    path = str(source.get("Path") or "")
    path_ext = path.rsplit(".", 1)[-1].lower() if "." in path else ""
    if path_ext in supported:
        return path_ext

    container = str(source.get("Container") or "")
    tokens = [token.strip().lower() for token in container.split(",")]
    for candidate in ("mp4", "m4v", "mov"):
        if candidate in tokens:
            return candidate
    return None


def redact_url(url: str) -> str:
    parts = urllib.parse.urlsplit(url)
    query = [
        (key, "<redacted>" if key.lower() == "api_key" else value)
        for key, value in urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    ]
    return urllib.parse.urlunsplit(
        (parts.scheme, parts.netloc, parts.path, urllib.parse.urlencode(query), parts.fragment)
    )


def media_streams(source: dict, stream_type: str) -> list[dict]:
    return [
        stream
        for stream in source.get("MediaStreams") or []
        if str(stream.get("Type", "")).lower() == stream_type.lower()
    ]


def has_hdr_metadata(source: dict) -> bool:
    values: list[str] = []
    for key in ("VideoRange", "VideoRangeType"):
        value = source.get(key)
        if value:
            values.append(str(value))
    for stream in media_streams(source, "Video"):
        for key in ("VideoRange", "VideoRangeType", "ColorTransfer", "ColorPrimaries"):
            value = stream.get(key)
            if value:
                values.append(str(value))
    joined = " ".join(values).lower()
    return any(token in joined for token in ("hdr", "pq", "smpte2084", "hlg", "bt2020"))


def has_dolby_vision_metadata(source: dict) -> bool:
    values: list[str] = []
    for key in ("VideoDoViTitle", "VideoRange", "VideoRangeType", "VideoCodec"):
        value = source.get(key)
        if value:
            values.append(str(value))
    for stream in media_streams(source, "Video"):
        for key in ("VideoDoViTitle", "DvProfile", "DolbyVisionProfile", "Codec", "Profile"):
            value = stream.get(key)
            if value:
                values.append(str(value))
    joined = " ".join(values).lower()
    return any(token in joined for token in ("dovi", "dolby vision", "dvhe", "dvh1"))


def probe_static_stream(url: str, session: Session, required_headers: Dict[str, str]) -> tuple[int, str, int]:
    headers = dict(required_headers)
    headers["Range"] = "bytes=0-65535"
    status, response_headers, body = request(url, token=session.token, headers=headers, read_limit=65_536)
    content_type = response_headers.get("Content-Type") or response_headers.get("content-type") or ""
    if status not in (200, 206):
        raise ProbeFailure(f"static_stream_http_{status}")
    if not body:
        raise ProbeFailure("static_stream_empty_body")
    if "mpegurl" in content_type.lower() or "m3u8" in content_type.lower():
        raise ProbeFailure(f"static_stream_returned_hls content_type={content_type}")
    return status, content_type, len(body)


def container_matches(container: str, required_tokens: tuple[str, ...]) -> bool:
    lowered = container.lower()
    return any(token in lowered for token in required_tokens)


def run_target(server_url: str, session: Session, target: ProbeTarget) -> None:
    info = fetch_playback_info(server_url, session, target.item_id)
    source = selected_source(info, target.item_id)

    container = str(source.get("Container") or "")
    video_codec = str(source.get("VideoCodec") or "")
    audio_codec = str(source.get("AudioCodec") or "")
    supports_direct_play = bool(source.get("SupportsDirectPlay"))
    supports_direct_stream = bool(source.get("SupportsDirectStream"))
    required_headers = source.get("RequiredHttpHeaders") or {}

    if target.required_container_tokens and not container_matches(container, target.required_container_tokens):
        raise ProbeFailure(f"unexpected_container={container}")
    if target.require_server_direct_play and not supports_direct_play:
        raise ProbeFailure("server_reported_supports_direct_play=false")
    if target.require_hdr and not has_hdr_metadata(source):
        raise ProbeFailure("missing_hdr_metadata")
    if target.require_dolby_vision and not has_dolby_vision_metadata(source):
        raise ProbeFailure("missing_dolby_vision_metadata")

    url = stream_url(server_url, target.item_id, source, session.token)
    status, content_type, byte_count = probe_static_stream(url, session, required_headers)

    print(
        "PASS "
        f"{target.label} item={target.item_id[:8]} "
        f"container={container or 'unknown'} video={video_codec or 'unknown'} audio={audio_codec or 'unknown'} "
        f"supportsDirectPlay={supports_direct_play} supportsDirectStream={supports_direct_stream} "
        f"staticStatus={status} bytes={byte_count} contentType={content_type or 'unknown'} "
        f"url={redact_url(url)}"
    )


def configured_targets() -> list[ProbeTarget]:
    mkv_item_id = os.environ.get("TEST_MKV_ITEM_ID") or os.environ.get("TEST_MKV_DOLBY_VISION_ITEM_ID") or ""
    dolby_vision_item_id = (
        os.environ.get("TEST_DOLBY_VISION_ITEM_ID")
        or os.environ.get("TEST_DIRECTPLAY_DOLBY_VISION_ITEM_ID")
        or os.environ.get("TEST_MKV_DOLBY_VISION_ITEM_ID")
        or ""
    )
    hdr_item_id = os.environ.get("TEST_HDR_ITEM_ID") or dolby_vision_item_id
    specs = [
        ProbeTarget(
            label="directplay_mp4",
            item_id=normalized_item_id(os.environ.get("TEST_DIRECTPLAY_MP4_ITEM_ID", "")),
            required_container_tokens=("mp4", "mov", "m4v"),
            require_server_direct_play=True,
        ),
        ProbeTarget(
            label="mkv_original",
            item_id=normalized_item_id(mkv_item_id),
            required_container_tokens=("mkv", "matroska"),
        ),
        ProbeTarget(
            label="hdr_original",
            item_id=normalized_item_id(hdr_item_id),
            require_hdr=True,
        ),
        ProbeTarget(
            label="dolby_vision_original",
            item_id=normalized_item_id(dolby_vision_item_id),
            require_hdr=True,
            require_dolby_vision=True,
        ),
    ]
    return [spec for spec in specs if spec.item_id and spec.item_id != "..."]


def validate_environment() -> tuple[str, str, str]:
    server_url = os.environ.get("JELLYFIN_BASE_URL") or os.environ.get("REELFIN_TEST_SERVER_URL") or ""
    username = os.environ.get("JELLYFIN_USERNAME") or os.environ.get("REELFIN_TEST_USERNAME") or ""
    password = os.environ.get("JELLYFIN_PASSWORD") or os.environ.get("REELFIN_TEST_PASSWORD") or ""
    missing = [
        name
        for name, value in (
            ("JELLYFIN_BASE_URL", server_url),
            ("JELLYFIN_USERNAME", username),
            ("JELLYFIN_PASSWORD", password),
        )
        if not value or value == "..."
    ]
    if missing:
        raise ProbeFailure("missing_env=" + ",".join(missing))
    if not configured_targets():
        raise ProbeFailure("missing_item_ids")
    return server_url, username, password


def main() -> int:
    try:
        server_url, username, password = validate_environment()
        session = authenticate(server_url, username, password)
        failures: list[str] = []
        for target in configured_targets():
            try:
                run_target(server_url, session, target)
            except ProbeFailure as error:
                failures.append(f"FAIL {target.label} item={target.item_id[:8]} reason={error}")

        for failure in failures:
            print(failure)
        print(f"Summary: {len(configured_targets()) - len(failures)}/{len(configured_targets())} explicit item probes passed.")
        return 1 if failures else 0
    except ProbeFailure as error:
        print(f"Probe error: {error}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
