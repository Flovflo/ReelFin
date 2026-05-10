#!/usr/bin/env python3
"""Unit tests for ReelFin deep playback evidence checks."""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import tempfile
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


deep = load_script_module("assert_player_deep_playback_evidence")


class PlayerDeepPlaybackEvidenceTests(unittest.TestCase):
    def evaluate(self, runtime: str, benchmark: str = ""):
        with tempfile.TemporaryDirectory() as temp_dir:
            run_dir = pathlib.Path(temp_dir)
            (run_dir / "ios-live-ui-runtime.stream").write_text(runtime, encoding="utf-8")
            (run_dir / "original-stream-benchmark.log").write_text(benchmark, encoding="utf-8")
            return deep.evaluate_paths(
                [run_dir],
                deep.EvidenceConfig(
                    min_observed_seconds=20,
                    min_ticks=3,
                    require_dv=True,
                    require_samplebuffer=True,
                ),
            )

    def test_passes_with_advancing_avplayer_and_samplebuffer_evidence(self) -> None:
        result = self.evaluate(
            runtime="""
playback.audio.selection - session=abc item=movie track='Main' codec=eac3 default=true
playback.proof - session=abc item=movie resolution=3840x2160 codec=hvc1 bitDepth=10 hdr=PQ dv=true method=DirectPlay observedBitrate=123
[NB-DIAG] avplayer.first-frame - session=abc item=movie elapsedMs=900 currentTime=10.000
playback.ttff - session=abc item=movie totalMs=950 method=DirectPlay
playback.deep.tick - session=abc item=movie current=10.000 delta=0.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=25.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=abc item=movie current=18.000 delta=8.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=24.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=abc item=movie current=26.000 delta=8.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=23.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=abc item=movie current=34.000 delta=8.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=22.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
nativeplayer.sampleBuffer.route.selected - source=mkv123 avPlayerItem=false avPlayerViewController=false serverTranscodeUsed=false
nativeplayer.playbackPlan.created - source=mkv123 canStart=true demuxer=MatroskaDemuxer video=VideoToolbox audio=AVSampleBufferAudioRenderer
nativeplayer.deep.tick - item=mkv123 current=6.000 delta=6.000 state=playing videoPackets=42 audioPackets=41 audioSamples=2048 audioRenderer=AVSampleBufferAudioRenderer droppedFrames=0 audioUnderruns=0 audioRebuffers=0
""",
            benchmark="""
PASS mkv_original item=mkv123 api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3 checks=matroska_ebml_header_present,native_samplebuffer_original_contract
""",
        )

        self.assertFalse(result.findings)
        self.assertEqual(result.avplayer_session_count, 1)
        self.assertEqual(result.samplebuffer_tick_count, 1)

    def test_fails_when_first_frame_has_no_continuous_ticks(self) -> None:
        result = self.evaluate(
            runtime="""
playback.audio.selection - session=abc item=movie track='Main' codec=eac3 default=true
playback.proof - session=abc item=movie resolution=3840x2160 codec=hvc1 bitDepth=10 hdr=PQ dv=true method=DirectPlay
[NB-DIAG] avplayer.first-frame - session=abc item=movie elapsedMs=900 currentTime=10.000
playback.ttff - session=abc item=movie totalMs=950 method=DirectPlay
nativeplayer.sampleBuffer.route.selected - source=mkv123 avPlayerItem=false avPlayerViewController=false
nativeplayer.playbackPlan.created - source=mkv123 canStart=true demuxer=MatroskaDemuxer video=VideoToolbox audio=AVSampleBufferAudioRenderer
nativeplayer.deep.tick - item=mkv123 current=6.000 delta=6.000 state=playing videoPackets=42 audioPackets=41 audioSamples=2048 audioRenderer=AVSampleBufferAudioRenderer droppedFrames=0 audioUnderruns=0 audioRebuffers=0
""",
            benchmark="PASS mkv_original item=mkv123 api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
        )

        self.assertIn("avplayer_deep_ticks_below_minimum", result.finding_labels())

    def test_fails_when_ticks_do_not_advance_enough(self) -> None:
        result = self.evaluate(
            runtime="""
playback.audio.selection - session=abc item=movie track='Main' codec=eac3 default=true
playback.proof - session=abc item=movie resolution=3840x2160 codec=hvc1 bitDepth=10 hdr=PQ dv=true method=DirectPlay
[NB-DIAG] avplayer.first-frame - session=abc item=movie elapsedMs=900 currentTime=10.000
playback.ttff - session=abc item=movie totalMs=950 method=DirectPlay
playback.deep.tick - session=abc item=movie current=10.000 delta=0.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=25.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=abc item=movie current=11.000 delta=1.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=24.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=abc item=movie current=12.000 delta=1.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=23.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
nativeplayer.sampleBuffer.route.selected - source=mkv123 avPlayerItem=false avPlayerViewController=false
nativeplayer.playbackPlan.created - source=mkv123 canStart=true demuxer=MatroskaDemuxer video=VideoToolbox audio=AVSampleBufferAudioRenderer
nativeplayer.deep.tick - item=mkv123 current=6.000 delta=6.000 state=playing videoPackets=42 audioPackets=41 audioSamples=2048 audioRenderer=AVSampleBufferAudioRenderer droppedFrames=0 audioUnderruns=0 audioRebuffers=0
""",
            benchmark="PASS mkv_original item=mkv123 api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
        )

        self.assertIn("avplayer_observed_progress_below_minimum", result.finding_labels())

    def test_fails_when_dolby_vision_is_required_but_missing(self) -> None:
        result = self.evaluate(
            runtime="""
playback.audio.selection - session=abc item=movie track='Main' codec=eac3 default=true
playback.proof - session=abc item=movie resolution=3840x2160 codec=hvc1 bitDepth=10 hdr=PQ dv=false method=DirectPlay
[NB-DIAG] avplayer.first-frame - session=abc item=movie elapsedMs=900 currentTime=10.000
playback.ttff - session=abc item=movie totalMs=950 method=DirectPlay
playback.deep.tick - session=abc item=movie current=10.000 delta=0.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=25.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=abc item=movie current=20.000 delta=10.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=24.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=abc item=movie current=31.000 delta=11.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=23.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
nativeplayer.sampleBuffer.route.selected - source=mkv123 avPlayerItem=false avPlayerViewController=false
nativeplayer.playbackPlan.created - source=mkv123 canStart=true demuxer=MatroskaDemuxer video=VideoToolbox audio=AVSampleBufferAudioRenderer
nativeplayer.deep.tick - item=mkv123 current=6.000 delta=6.000 state=playing videoPackets=42 audioPackets=41 audioSamples=2048 audioRenderer=AVSampleBufferAudioRenderer droppedFrames=0 audioUnderruns=0 audioRebuffers=0
""",
            benchmark="PASS mkv_original item=mkv123 api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
        )

        self.assertIn("dolby_vision_evidence_missing", result.finding_labels())

    def test_fails_when_samplebuffer_route_is_required_but_missing(self) -> None:
        result = self.evaluate(
            runtime="""
playback.audio.selection - session=abc item=movie track='Main' codec=eac3 default=true
playback.proof - session=abc item=movie resolution=3840x2160 codec=hvc1 bitDepth=10 hdr=PQ dv=true method=DirectPlay
[NB-DIAG] avplayer.first-frame - session=abc item=movie elapsedMs=900 currentTime=10.000
playback.ttff - session=abc item=movie totalMs=950 method=DirectPlay
playback.deep.tick - session=abc item=movie current=10.000 delta=0.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=25.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=abc item=movie current=20.000 delta=10.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=24.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=abc item=movie current=31.000 delta=11.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=23.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
""",
        )

        self.assertIn("samplebuffer_route_evidence_missing", result.finding_labels())


if __name__ == "__main__":
    unittest.main()
