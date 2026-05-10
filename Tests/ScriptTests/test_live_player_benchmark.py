#!/usr/bin/env python3
"""Unit tests for the live player benchmark diagnostics."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"


def load_script_module(name: str):
    sys.path.insert(0, str(SCRIPTS_DIR))
    spec = importlib.util.spec_from_file_location(name, SCRIPTS_DIR / f"{name}.py")
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


benchmark = load_script_module("live_player_benchmark")


class LivePlayerBenchmarkTests(unittest.TestCase):
    def test_source_codecs_fall_back_to_media_streams(self) -> None:
        source = {
            "VideoCodec": "",
            "AudioCodec": None,
            "MediaStreams": [
                {"Type": "Video", "Codec": "hevc"},
                {"Type": "Audio", "Codec": "eac3"},
            ],
        }

        self.assertEqual(benchmark.source_codecs(source), ("hevc", "eac3"))

    def test_nonzero_range_must_return_partial_content(self) -> None:
        sample = benchmark.RangeSample(
            offset=1_000_000,
            status=200,
            bytes_read=65_536,
            elapsed_ms=40,
        )
        failures: list[str] = []

        benchmark.validate_range_contract(
            sample=sample,
            response_headers={"Content-Length": "10000000"},
            content_length=10_000_000,
            byte_count=65_536,
            failures=failures,
        )

        self.assertIn("seek_range_not_partial_content@1000000", failures)

    def test_large_first_range_ignored_is_reported_but_not_fatal(self) -> None:
        sample = benchmark.RangeSample(
            offset=0,
            status=200,
            bytes_read=65_536,
            elapsed_ms=40,
        )
        failures: list[str] = []
        warnings: list[str] = []

        benchmark.validate_range_contract(
            sample=sample,
            response_headers={"Content-Length": "10000000"},
            content_length=10_000_000,
            byte_count=65_536,
            failures=failures,
            warnings=warnings,
        )

        self.assertEqual(failures, [])
        self.assertIn("startup_zero_range_ignored", warnings)

    def test_partial_content_must_match_requested_offset(self) -> None:
        sample = benchmark.RangeSample(
            offset=1_000_000,
            status=206,
            bytes_read=65_536,
            elapsed_ms=40,
        )
        failures: list[str] = []

        benchmark.validate_range_contract(
            sample=sample,
            response_headers={"Content-Range": "bytes 0-65535/10000000"},
            content_length=10_000_000,
            byte_count=65_536,
            failures=failures,
        )

        self.assertIn("seek_content_range_mismatch@1000000", failures)

    def test_unknown_codecs_are_benchmark_failures(self) -> None:
        failures: list[str] = []
        checks: list[str] = []

        benchmark.validate_codec_metadata(
            video_codec="unknown",
            audio_codec="unknown",
            failures=failures,
            checks=checks,
        )

        self.assertEqual(
            failures,
            ["missing_video_codec_metadata", "missing_audio_codec_metadata"],
        )


if __name__ == "__main__":
    unittest.main()
