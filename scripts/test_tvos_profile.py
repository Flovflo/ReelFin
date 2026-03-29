#!/usr/bin/env python3
"""Test what Jellyfin returns for MKV files with the tvOS device profile."""

import json
import os
import sys
import urllib.parse
import urllib.request
from urllib.error import HTTPError

SERVER = os.environ.get("JELLYFIN_SERVER", "https://jellyfin.taffin.ovh")
USERNAME = os.environ.get("JELLYFIN_USER", "")
PASSWORD = os.environ.get("JELLYFIN_PASS", "")

TVOS_DEVICE_PROFILE = {
    "Name": "ReelFin tvOS Apple TV (DV/HDR/Atmos)",
    "Id": "a3c1f8e2-7b5d-4a9e-b6c0-d2e4f8a1b3c5",
    "MaxStreamingBitrate": 80_000_000,
    "MusicStreamingTranscodingBitrate": 192_000,
    "DirectPlayProfiles": [
        {"Container": "mp4,m4v,mov", "AudioCodec": "aac,ac3,eac3,mp3,alac,flac", "VideoCodec": "hevc,h265,hvc1,dvh1,dvhe,h264,avc1", "Type": "Video"},
        {"Container": "mpegts", "AudioCodec": "aac,ac3,eac3", "VideoCodec": "hevc,h264", "Type": "Video"},
    ],
    "TranscodingProfiles": [
        {
            "Container": "fmp4",
            "Type": "Video",
            "VideoCodec": "hevc,h264",
            "AudioCodec": "eac3,aac",
            "Protocol": "hls",
            "Context": "Streaming",
            "MaxAudioChannels": "8",
            "EnableSubtitlesinManifest": False,
            "EstimateContentLength": False,
            "CopyTimestamps": True,
            "EnableAudioVbrEncoding": True,
        }
    ],
    "SubtitleProfiles": [
        {"Format": "srt", "Method": "External"},
        {"Format": "vtt", "Method": "External"},
        {"Format": "ass", "Method": "External"},
        {"Format": "ssa", "Method": "External"},
    ],
    "ResponseProfiles": [
        {"Type": "Video", "Container": "m4v", "MimeType": "video/mp4"}
    ],
}


def emby_auth(token=None):
    parts = ['Client="ReelFin"', 'Device="AppleTV"', 'DeviceId="tvos-test"', 'Version="1.0"']
    if token:
        parts.append(f'Token="{token}"')
    return "MediaBrowser " + ", ".join(parts)


def api_request(url, method="GET", token=None, body=None):
    headers = {
        "User-Agent": "ReelFin/1.0",
        "X-Emby-Authorization": emby_auth(token),
        "Accept": "application/json",
    }
    if token:
        headers["X-Emby-Token"] = token
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, method=method, headers=headers, data=data)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, json.loads(resp.read())
    except HTTPError as e:
        body = e.read()
        try:
            return e.code, json.loads(body) if body else {}
        except Exception:
            return e.code, {"error": body.decode("utf-8", "replace") if body else ""}


def authenticate():
    status, data = api_request(
        f"{SERVER}/Users/AuthenticateByName",
        method="POST",
        body={"Username": USERNAME, "Pw": PASSWORD},
    )
    if status != 200:
        print(f"Auth failed: {status}")
        sys.exit(1)
    return data["User"]["Id"], data["AccessToken"]


def fetch_items(user_id, token, limit=20):
    status, data = api_request(
        f"{SERVER}/Users/{user_id}/Items?Recursive=true&IncludeItemTypes=Movie,Episode&Limit={limit}&SortBy=DateCreated&SortOrder=Descending",
        token=token,
    )
    if status != 200:
        return []
    return data.get("Items", [])


def fetch_playback_info(item_id, user_id, token):
    body = {
        "UserId": user_id,
        "EnableDirectPlay": True,
        "EnableDirectStream": True,
        "EnableTranscoding": True,
        "MaxStreamingBitrate": 80_000_000,
        "AllowVideoStreamCopy": True,
        "AllowAudioStreamCopy": True,
        "DeviceProfile": TVOS_DEVICE_PROFILE,
    }
    status, data = api_request(
        f"{SERVER}/Items/{item_id}/PlaybackInfo",
        method="POST",
        token=token,
        body=body,
    )
    return status, data


def main():
    token = os.environ.get("JELLYFIN_TOKEN", "")
    user_id = os.environ.get("JELLYFIN_USER_ID", "")

    if not token:
        if not USERNAME or not PASSWORD:
            print("Set JELLYFIN_TOKEN or JELLYFIN_USER+JELLYFIN_PASS env vars")
            sys.exit(1)
        user_id, token = authenticate()

    if not user_id:
        # Fetch user ID from token
        status, data = api_request(f"{SERVER}/Users/Me", token=token)
        if status != 200:
            print(f"Failed to get user info: {status} {data}")
            # Try system info as fallback
            status2, data2 = api_request(f"{SERVER}/System/Info", token=token)
            print(f"System info: {status2}")
            sys.exit(1)
        user_id = data["Id"]

    print(f"Authenticated as {user_id}\n")

    items = fetch_items(user_id, token)
    print(f"Found {len(items)} items\n")

    for item in items:
        item_id = item["Id"]
        name = item.get("Name", "?")
        status, info = fetch_playback_info(item_id, user_id, token)
        if status != 200:
            print(f"  [{name}] PlaybackInfo failed: {status}")
            continue

        for src in info.get("MediaSources", []):
            container = src.get("Container", "?")
            video_codec = src.get("VideoCodec", "?")
            audio_codec = src.get("AudioCodec", "?")
            direct_play = src.get("SupportsDirectPlay", False)
            direct_stream = src.get("SupportsDirectStream", False)
            direct_stream_url = src.get("DirectStreamUrl")
            transcoding_url = src.get("TranscodingUrl")
            transcode_reasons = src.get("TranscodeReasons")

            tag = "MKV" if container and "mkv" in container.lower() else container.upper()
            print(f"[{tag}] {name}")
            print(f"  Container:          {container}")
            print(f"  Video:              {video_codec}")
            print(f"  Audio:              {audio_codec}")
            print(f"  SupportsDirectPlay: {direct_play}")
            print(f"  SupportsDirectStream: {direct_stream}")
            print(f"  DirectStreamUrl:    {direct_stream_url[:120] if direct_stream_url else 'None'}")
            print(f"  TranscodingUrl:     {transcoding_url[:120] if transcoding_url else 'None'}")
            print(f"  TranscodeReasons:   {transcode_reasons}")
            print()


if __name__ == "__main__":
    main()
