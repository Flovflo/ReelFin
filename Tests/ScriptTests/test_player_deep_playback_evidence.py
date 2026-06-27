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
    def evaluate(
        self,
        runtime: str,
        benchmark: str = "",
        required_avplayer_items: tuple[object, ...] = (),
        min_observed_seconds: float = 20,
    ):
        with tempfile.TemporaryDirectory() as temp_dir:
            run_dir = pathlib.Path(temp_dir)
            (run_dir / "ios-live-ui-runtime.stream").write_text(runtime, encoding="utf-8")
            (run_dir / "original-stream-benchmark.log").write_text(benchmark, encoding="utf-8")
            return deep.evaluate_paths(
                [run_dir],
                deep.EvidenceConfig(
                    min_observed_seconds=min_observed_seconds,
                    min_ticks=3,
                    require_dv=True,
                    require_samplebuffer=True,
                    required_avplayer_items=required_avplayer_items,
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

    def test_fails_when_long_directplay_only_advances_twenty_eight_seconds(self) -> None:
        result = self.evaluate(
            runtime="""
playback.audio.selection - session=dv1 item=2050da6b track='French' codec=eac3 default=true
playback.proof - session=dv1 item=2050da6b resolution=3840x1608 codec=hvc1 bitDepth=10 hdr=PQ dv=true method=DirectPlay
[NB-DIAG] avplayer.first-frame - session=dv1 item=2050da6b elapsedMs=900 currentTime=130.000
playback.ttff - session=dv1 item=2050da6b totalMs=950 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=130.000 delta=0.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=25.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=144.000 delta=14.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=12.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=158.000 delta=14.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=0.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
nativeplayer.sampleBuffer.route.selected - source=mkv123 avPlayerItem=false avPlayerViewController=false
nativeplayer.playbackPlan.created - source=mkv123 canStart=true demuxer=MatroskaDemuxer video=VideoToolbox audio=AVSampleBufferAudioRenderer
nativeplayer.deep.tick - item=mkv123 current=6.000 delta=6.000 state=playing videoPackets=42 audioPackets=41 audioSamples=2048 audioRenderer=AVSampleBufferAudioRenderer droppedFrames=0 audioUnderruns=0 audioRebuffers=0
""",
            benchmark="PASS mkv_original item=mkv123 api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
            required_avplayer_items=(
                deep.RequiredAVPlayerItem(item_id="2050da6b10e0636851bb6d00249ee38b", min_observed_seconds=75, require_dv=True),
            ),
        )

        self.assertIn("required_avplayer_observed_progress_below_minimum", result.finding_labels())

    def test_fails_when_best_session_passes_but_required_dv_session_stalls(self) -> None:
        result = self.evaluate(
            runtime="""
playback.audio.selection - session=mp4 item=plainmp4 track='Main' codec=aac default=true
playback.proof - session=mp4 item=plainmp4 resolution=1920x1080 codec=avc1 bitDepth=8 hdr=SDR dv=false method=DirectPlay
[NB-DIAG] avplayer.first-frame - session=mp4 item=plainmp4 elapsedMs=900 currentTime=10.000
playback.ttff - session=mp4 item=plainmp4 totalMs=950 method=DirectPlay
playback.deep.tick - session=mp4 item=plainmp4 current=10.000 delta=0.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=25.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=mp4 item=plainmp4 current=50.000 delta=40.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=25.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=mp4 item=plainmp4 current=90.000 delta=40.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=25.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.audio.selection - session=dv1 item=2050da6b track='French' codec=eac3 default=true
playback.proof - session=dv1 item=2050da6b resolution=3840x1608 codec=hvc1 bitDepth=10 hdr=PQ dv=true method=DirectPlay
[NB-DIAG] avplayer.first-frame - session=dv1 item=2050da6b elapsedMs=900 currentTime=130.000
playback.ttff - session=dv1 item=2050da6b totalMs=950 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=130.000 delta=0.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=20.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=144.000 delta=14.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=2.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=158.000 delta=14.000 rate=0.0 timeControl=waiting itemStatus=readyToPlay likely=false buffered=0.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
nativeplayer.sampleBuffer.route.selected - source=mkv123 avPlayerItem=false avPlayerViewController=false
nativeplayer.playbackPlan.created - source=mkv123 canStart=true demuxer=MatroskaDemuxer video=VideoToolbox audio=AVSampleBufferAudioRenderer
nativeplayer.deep.tick - item=mkv123 current=6.000 delta=6.000 state=playing videoPackets=42 audioPackets=41 audioSamples=2048 audioRenderer=AVSampleBufferAudioRenderer droppedFrames=0 audioUnderruns=0 audioRebuffers=0
""",
            benchmark="PASS mkv_original item=mkv123 api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
            required_avplayer_items=(
                deep.RequiredAVPlayerItem(item_id="2050da6b10e0636851bb6d00249ee38b", min_observed_seconds=75, require_dv=True),
            ),
        )

        self.assertIn("required_avplayer_observed_progress_below_minimum", result.finding_labels())

    def test_fails_when_poststart_rebuffer_wait_has_no_ready_recovery(self) -> None:
        result = self.evaluate(
            runtime="""
playback.audio.selection - session=dv1 item=2050da6b track='French' codec=eac3 default=true
playback.proof - session=dv1 item=2050da6b resolution=3840x1608 codec=hvc1 bitDepth=10 hdr=PQ dv=true method=DirectPlay
[NB-DIAG] avplayer.first-frame - session=dv1 item=2050da6b elapsedMs=900 currentTime=130.000
playback.ttff - session=dv1 item=2050da6b totalMs=950 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=130.000 delta=0.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=25.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=170.000 delta=40.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=18.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=210.000 delta=40.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=12.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.directplay.poststart_rebuffer.wait - session=dv1 item=2050da6b recentStalls=1 elapsed=43.7s firstFrameElapsed=42.2s buffered=0.0 target=24.0 timeout=30.0 waits=false action=pause_current_item
nativeplayer.sampleBuffer.route.selected - source=mkv123 avPlayerItem=false avPlayerViewController=false
nativeplayer.playbackPlan.created - source=mkv123 canStart=true demuxer=MatroskaDemuxer video=VideoToolbox audio=AVSampleBufferAudioRenderer
nativeplayer.deep.tick - item=mkv123 current=6.000 delta=6.000 state=playing videoPackets=42 audioPackets=41 audioSamples=2048 audioRenderer=AVSampleBufferAudioRenderer droppedFrames=0 audioUnderruns=0 audioRebuffers=0
""",
            benchmark="PASS mkv_original item=mkv123 api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
            required_avplayer_items=(
                deep.RequiredAVPlayerItem(item_id="2050da6b10e0636851bb6d00249ee38b", min_observed_seconds=75, require_dv=True),
            ),
        )

        self.assertIn("required_avplayer_poststart_rebuffer_unresolved", result.finding_labels())

    def test_passes_when_required_dv_session_advances_beyond_long_threshold(self) -> None:
        result = self.evaluate(
            runtime="""
playback.audio.selection - session=dv1 item=2050da6b track='French' codec=eac3 default=true
playback.proof - session=dv1 item=2050da6b resolution=3840x1608 codec=hvc1 bitDepth=10 hdr=PQ dv=true method=DirectPlay
[NB-DIAG] avplayer.first-frame - session=dv1 item=2050da6b elapsedMs=900 currentTime=130.000
playback.ttff - session=dv1 item=2050da6b totalMs=950 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=130.000 delta=0.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=30.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=170.000 delta=40.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=28.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
playback.deep.tick - session=dv1 item=2050da6b current=210.000 delta=40.000 rate=1.0 timeControl=playing itemStatus=readyToPlay likely=true buffered=25.0 droppedFrames=0 observedBitrate=123 method=DirectPlay
nativeplayer.sampleBuffer.route.selected - source=mkv123 avPlayerItem=false avPlayerViewController=false
nativeplayer.playbackPlan.created - source=mkv123 canStart=true demuxer=MatroskaDemuxer video=VideoToolbox audio=AVSampleBufferAudioRenderer
nativeplayer.deep.tick - item=mkv123 current=6.000 delta=6.000 state=playing videoPackets=42 audioPackets=41 audioSamples=2048 audioRenderer=AVSampleBufferAudioRenderer droppedFrames=0 audioUnderruns=0 audioRebuffers=0
""",
            benchmark="PASS mkv_original item=mkv123 api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
            required_avplayer_items=(
                deep.RequiredAVPlayerItem(item_id="2050da6b10e0636851bb6d00249ee38b", min_observed_seconds=75, require_dv=True),
            ),
        )

        self.assertFalse(result.findings)


if __name__ == "__main__":
    unittest.main()
