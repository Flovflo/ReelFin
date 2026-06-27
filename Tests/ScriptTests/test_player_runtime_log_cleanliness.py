#!/usr/bin/env python3
"""Unit tests for ReelFin runtime log cleanliness checks."""

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


runtime_clean = load_script_module("assert_player_runtime_log_clean")


class PlayerRuntimeLogCleanlinessTests(unittest.TestCase):
    def test_detects_password_accessibility_value_leak(self) -> None:
        line = (
            "First responder: <UITextField: 0x123; text = 's...t' "
            "(length = 12); placeholder = Password; layer = <CALayer>>"
        )

        matches = [
            label
            for label, pattern in runtime_clean.FORBIDDEN_REGEXES
            if pattern.search(line)
        ]

        self.assertIn("RAW_PASSWORD_ACCESSIBILITY_VALUE", matches)

    def test_redacts_password_accessibility_value_in_findings(self) -> None:
        line = (
            "First responder: <UITextField: 0x123; text = 's...t' "
            "(length = 12); placeholder = Password; layer = <CALayer>>"
        )

        redacted = runtime_clean.redact_sensitive(line)

        self.assertIn("text = '<redacted>'", redacted)
        self.assertNotIn("s...t", redacted)
        self.assertNotIn("length = 12", redacted)

    def test_detects_poststart_rebuffer_timeout_as_fatal(self) -> None:
        line = (
            "playback.directplay.poststart_rebuffer.timeout - session=dv1 "
            "item=2050da6b recentStalls=1 buffered=0.0 target=24.0"
        )

        matches = [
            label
            for label, pattern in runtime_clean.FORBIDDEN_PATTERNS
            if pattern in line
        ]

        self.assertIn("POSTSTART_REBUFFER_TIMEOUT", matches)

    def test_ignores_avfoundation_cancelled_loopback_range_probe(self) -> None:
        line = (
            'Task <ABC>.<2> finished with error [-999] Error Domain=NSURLErrorDomain '
            'Code=-999 "cancelled" UserInfo={NSErrorFailingURLStringKey='
            'http://127.0.0.1:62086/media/item.mp4, NSLocalizedDescription=cancelled}'
        )

        self.assertTrue(
            runtime_clean.is_ignorable_line(
                "LOCAL_GATEWAY_LOOPBACK_FAILURE",
                line,
                runtime_clean.LogContext(ignores_ios_simulator_hdr_dv_render_noise=False),
            )
        )

    def test_non_cancelled_loopback_failure_stays_fatal(self) -> None:
        line = (
            'Task <ABC>.<2> finished with error [-1005] Error Domain=NSURLErrorDomain '
            'Code=-1005 "The network connection was lost." UserInfo={NSErrorFailingURLStringKey='
            'http://127.0.0.1:62086/media/item.mp4}'
        )

        self.assertFalse(
            runtime_clean.is_ignorable_line(
                "LOCAL_GATEWAY_LOOPBACK_FAILURE",
                line,
                runtime_clean.LogContext(ignores_ios_simulator_hdr_dv_render_noise=False),
            )
        )

    def test_suffix_live_ui_logs_ignore_simulator_render_noise_after_successful_playback(self) -> None:
        text = """
playback.proof - session=dv1 item=657b41c0 hdr=PQ dv=true method=DirectPlay
[NB-DIAG] avplayer.first-frame - session=dv1 item=657b41c0 elapsedMs=900 currentTime=10.000
playback.ttff - session=dv1 item=657b41c0 totalMs=950 method=DirectPlay
"""

        context = runtime_clean.build_log_context(
            pathlib.Path("ios-live-ui-hdr-dv-long-runtime.stream"),
            text,
        )

        self.assertTrue(context.ignores_ios_simulator_hdr_dv_render_noise)

    def test_samplebuffer_live_ui_logs_ignore_simulator_render_noise_after_deep_ticks(self) -> None:
        text = """
nativeplayer.sampleBuffer.route.selected - source=mkv123 avPlayerItem=false avPlayerViewController=false
nativeplayer.deep.tick - item=mkv123 current=6.000 delta=6.000 state=playing videoPackets=42 audioPackets=41 audioSamples=2048 audioRenderer=AVSampleBufferAudioRenderer
"""

        context = runtime_clean.build_log_context(
            pathlib.Path("ios-live-ui-samplebuffer-runtime.stream"),
            text,
        )

        self.assertTrue(context.ignores_ios_simulator_hdr_dv_render_noise)


if __name__ == "__main__":
    unittest.main()
