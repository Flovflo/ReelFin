"""Unit tests for ReelFin typed deep playback evidence checks."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from unittest import mock


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
resume_target = load_script_module("live_ui_resume_target")


class PlayerDeepPlaybackEvidenceTests(unittest.TestCase):
    av_session = "0123456789abcdef"
    av_media = "fedcba9876543210"
    sample_session = "1111111111111111"
    sample_media = "2222222222222222"
    sample_source = "3333333333333333"

    def record(self, event: str, session: str | None = None, **fields: object) -> str:
        payload: dict[str, object] = {
            "event": event,
            "session": session or self.av_session,
            **fields,
        }
        return json.dumps(payload, separators=(",", ":"), sort_keys=True)

    def avplayer_evidence(
        self,
        *,
        session: str | None = None,
        media: str | None = None,
        dv: bool = True,
        currents: tuple[float, ...] = (10.0, 22.0, 34.0),
    ) -> str:
        session = session or self.av_session
        media = media or self.av_media
        lines = [
            self.record("audioSelection", session, media=media, codec="eac3", isDefault=True),
            self.record(
                "playbackProof",
                session,
                media=media,
                width=3840,
                height=2160,
                codec="hevc",
                dolbyVision=dv,
                hdr="pq",
                method="directPlay",
                observedBitrate=123_000_000,
            ),
            self.record("firstFrame", session, media=media, elapsedMilliseconds=900.0, currentSeconds=currents[0]),
            self.record("ttff", session, media=media, totalMilliseconds=950.0, method="directPlay"),
        ]
        lines.extend(
            self.record(
                "avPlayerTick",
                session,
                media=media,
                currentSeconds=current,
                deltaSeconds=0.0 if index == 0 else current - currents[index - 1],
                rate=1.0,
                timeControl="playing",
                itemStatus="readyToPlay",
                likelyToKeepUp=True,
                bufferedSeconds=24.0,
                droppedFrames=0,
                codec="eac3",
            )
            for index, current in enumerate(currents)
        )
        return "\n".join(lines)

    def samplebuffer_evidence(
        self,
        *,
        tick_session: str | None = None,
        tick_source: str | None = None,
    ) -> str:
        return "\n".join(
            [
                self.record(
                    "plan",
                    self.sample_session,
                    media=self.sample_media,
                    source=self.sample_source,
                    canStart=True,
                    demuxer="matroska",
                    videoBackend="videoToolbox",
                    audioBackend="sampleBufferAudioRenderer",
                ),
                self.record(
                    "routeSelection",
                    self.sample_session,
                    media=self.sample_media,
                    source=self.sample_source,
                    route="sampleBuffer",
                    avPlayerItem=False,
                    avPlayerViewController=False,
                    serverTranscodeUsed=False,
                ),
                self.record(
                    "sampleBufferTick",
                    tick_session or self.sample_session,
                    media=self.sample_media,
                    source=tick_source or self.sample_source,
                    currentSeconds=6.0,
                    deltaSeconds=6.0,
                    state="playing",
                    videoPackets=42,
                    audioPackets=41,
                    audioSamples=2048,
                    audioRenderer="sampleBufferAudioRenderer",
                    droppedFrames=0,
                    audioUnderruns=0,
                    audioRebuffers=0,
                ),
            ]
        )

    def evaluate(
        self,
        files: dict[str, str],
        *,
        required_scenarios: tuple[object, ...] = (),
        require_dv: bool = False,
        require_samplebuffer: bool = False,
        min_observed_seconds: float = 20.0,
    ):
        with tempfile.TemporaryDirectory() as temp_dir:
            run_dir = pathlib.Path(temp_dir)
            for name, contents in files.items():
                (run_dir / name).write_text(contents, encoding="utf-8")
            return deep.evaluate_paths(
                [run_dir],
                deep.EvidenceConfig(
                    min_observed_seconds=min_observed_seconds,
                    min_ticks=3,
                    require_dv=require_dv,
                    require_samplebuffer=require_samplebuffer,
                    required_avplayer_scenarios=required_scenarios,
                ),
            )

    def test_passes_with_scenario_scoped_opaque_avplayer_and_samplebuffer_evidence(self) -> None:
        result = self.evaluate(
            {
                "ios-live-ui-runtime.stream": self.avplayer_evidence(),
                "ios-live-ui-samplebuffer-runtime.stream": self.samplebuffer_evidence(),
                "original-stream-benchmark.log": "PASS mkv_original api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
            },
            required_scenarios=(
                deep.RequiredAVPlayerScenario("directplay-mp4", min_observed_seconds=20),
            ),
            require_dv=True,
            require_samplebuffer=True,
        )

        self.assertFalse(result.findings)
        self.assertEqual(result.avplayer_session_count, 1)
        self.assertEqual(result.samplebuffer_tick_count, 1)

    def test_required_dv_scenario_does_not_accept_another_scenario(self) -> None:
        result = self.evaluate(
            {
                "ios-live-ui-runtime.stream": self.avplayer_evidence(dv=True),
                "ios-live-ui-hdr-dv-long-runtime.stream": self.avplayer_evidence(
                    session="aaaaaaaaaaaaaaaa",
                    media="bbbbbbbbbbbbbbbb",
                    dv=False,
                    currents=(100.0, 140.0, 180.0),
                ),
            },
            required_scenarios=(
                deep.RequiredAVPlayerScenario(
                    "directplay-hdr-dv-long",
                    min_observed_seconds=75,
                    require_dv=True,
                    require_hdr=True,
                ),
            ),
        )

        self.assertIn("required_avplayer_dolby_vision_evidence_missing", result.finding_labels())

    def test_events_must_share_scenario_session_and_opaque_media(self) -> None:
        evidence = self.avplayer_evidence().replace(
            '"event":"firstFrame","media":"fedcba9876543210","session":"0123456789abcdef"',
            '"event":"firstFrame","media":"cccccccccccccccc","session":"aaaaaaaaaaaaaaaa"',
        )
        result = self.evaluate({"ios-live-ui-runtime.stream": evidence})

        self.assertIn("avplayer_startup_evidence_incomplete", result.finding_labels())

    def test_samplebuffer_tick_from_another_session_does_not_complete_route_evidence(self) -> None:
        result = self.evaluate(
            {
                "ios-live-ui-runtime.stream": self.avplayer_evidence(),
                "ios-live-ui-samplebuffer-runtime.stream": self.samplebuffer_evidence(
                    tick_session="aaaaaaaaaaaaaaaa"
                ),
                "original-stream-benchmark.log": "PASS mkv_original api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
            },
            require_samplebuffer=True,
        )

        self.assertIn("samplebuffer_correlated_evidence_missing", result.finding_labels())

    def test_samplebuffer_tick_from_another_source_does_not_complete_route_evidence(self) -> None:
        result = self.evaluate(
            {
                "ios-live-ui-runtime.stream": self.avplayer_evidence(),
                "ios-live-ui-samplebuffer-runtime.stream": self.samplebuffer_evidence(
                    tick_source="bbbbbbbbbbbbbbbb"
                ),
                "original-stream-benchmark.log": "PASS mkv_original api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
            },
            require_samplebuffer=True,
        )

        self.assertIn("samplebuffer_correlated_evidence_missing", result.finding_labels())

    def test_rejects_raw_identity_free_text_unknown_fields_and_malformed_correlations(self) -> None:
        malicious = "\n".join(
            [
                self.record(
                    "firstFrame",
                    "raw-session",
                    item="8930e2b5481eeaec213595eda347443b",
                    message="raw title\nserver/path",
                    elapsedMilliseconds=1,
                ),
                self.record("madeUpEvent", media=self.av_media),
            ]
        )
        result = self.evaluate({"ios-live-ui-runtime.stream": malicious})

        labels = result.finding_labels()
        self.assertIn("invalid_deep_evidence_schema", labels)
        combined = " ".join(finding.message for finding in result.findings)
        self.assertNotIn("8930e2b5481eeaec213595eda347443b", combined)
        self.assertNotIn("raw title", combined)
        self.assertNotIn("server/path", combined)

    def test_cli_contract_parses_scenario_not_item_identifier(self) -> None:
        required = deep.parse_required_avplayer_scenario(
            "directplay-hdr-dv-long:75:3:1:1",
            default_min_observed_seconds=20,
            default_min_ticks=3,
        )

        self.assertEqual(required.scenario, "directplay-hdr-dv-long")
        self.assertEqual(required.min_observed_seconds, 75)
        self.assertTrue(required.require_dv)
        self.assertFalse(hasattr(deep, "RequiredAVPlayerItem"))
        self.assertFalse(hasattr(deep, "parse_required_avplayer_item"))

    def test_rejects_poststart_stall_and_samplebuffer_audio_regression(self) -> None:
        avplayer = self.avplayer_evidence() + "\n" + self.record(
            "avPlayerTick",
            media=self.av_media,
            currentSeconds=34.0,
            deltaSeconds=0.0,
            rate=0.0,
            timeControl="waiting",
            itemStatus="readyToPlay",
            likelyToKeepUp=False,
            bufferedSeconds=0.0,
            droppedFrames=0,
            codec="eac3",
        )
        samplebuffer = self.samplebuffer_evidence().replace('"audioUnderruns":0', '"audioUnderruns":1')
        result = self.evaluate(
            {
                "ios-live-ui-runtime.stream": avplayer,
                "ios-live-ui-samplebuffer-runtime.stream": samplebuffer,
                "original-stream-benchmark.log": "PASS mkv_original api=NativeEngine+AVSampleBufferDisplayLayer container=mkv video=hevc audio=eac3",
            },
            require_samplebuffer=True,
        )

        self.assertIn("samplebuffer_audio_underrun", result.finding_labels())


class PlayerRunnerIdentityContractTests(unittest.TestCase):
    raw_item_id = "8930e2b5481eeaec213595eda347443b"

    def test_resume_target_uses_scenario_and_persists_no_media_identity(self) -> None:
        session = object()
        first_item = {"UserData": {"PlaybackPositionTicks": 50}, "RunTimeTicks": 2_000_000_000}
        verified_item = {"UserData": {"PlaybackPositionTicks": 1_000_000_000}, "RunTimeTicks": 2_000_000_000}
        with tempfile.TemporaryDirectory() as temp_dir, mock.patch.dict(
            resume_target.os.environ,
            {"TEST_DIRECTPLAY_MP4_ITEM_ID": self.raw_item_id},
            clear=False,
        ), mock.patch.object(
            resume_target, "load_session", return_value=("https://example.invalid", session)
        ), mock.patch.object(
            resume_target.resume_probe, "fetch_item", side_effect=[first_item, verified_item]
        ), mock.patch.object(
            resume_target.resume_probe, "report_stopped_position"
        ), mock.patch.object(
            resume_target.time, "sleep"
        ):
            state_file = pathlib.Path(temp_dir) / "state.json"
            output = StringIO()
            with redirect_stdout(output):
                resume_target.prepare("directplay-mp4", state_file)

            state = json.loads(state_file.read_text(encoding="utf-8"))
            self.assertEqual(state["scenario"], "directplay-mp4")
            self.assertNotIn("item_id", state)
            self.assertNotIn(self.raw_item_id, state_file.read_text(encoding="utf-8"))
            self.assertNotIn(self.raw_item_id[:8], output.getvalue())

    def test_runner_contract_has_no_raw_item_argv_state_or_evidence_selector(self) -> None:
        runner = (SCRIPTS_DIR / "run_reelfin_player_e2e.sh").read_text(encoding="utf-8")
        target = (SCRIPTS_DIR / "live_ui_resume_target.py").read_text(encoding="utf-8")
        combined = runner + "\n" + target

        for forbidden in [
            "--require-avplayer-item",
            "--item-id",
            '"item_id":',
            "REELFIN_LIVE_UI_TARGET_ITEM_ID",
        ]:
            self.assertNotIn(forbidden, combined)
        self.assertIn("--require-avplayer-scenario", runner)
        self.assertIn("REELFIN_LIVE_UI_TARGET_SCENARIO", runner)

    def test_app_launch_contract_forwards_only_closed_scenario_not_fixture_item_ids(self) -> None:
        runner = (SCRIPTS_DIR / "run_reelfin_player_e2e.sh").read_text(encoding="utf-8")
        home = (REPO_ROOT / "ReelFinUI/Sources/ReelFinUI/Home/HomeView.swift").read_text(encoding="utf-8")
        ui_test = (REPO_ROOT / "Tests/ReelFinUITests/PlaybackLiveSmokeUITests.swift").read_text(encoding="utf-8")

        self.assertNotRegex(runner, r"SIMCTL_CHILD_TEST_[A-Z0-9_]*ITEM_ID")
        self.assertNotRegex(home, r"TEST_[A-Z0-9_]*ITEM_ID")
        self.assertNotIn("explicitTargetItemID", ui_test)
        self.assertNotRegex(ui_test, r'"TEST_[A-Z0-9_]*ITEM_ID"')
        self.assertIn("REELFIN_LIVE_UI_TARGET_SCENARIO", runner)
        self.assertIn("REELFIN_LIVE_UI_TARGET_SCENARIO", home)

    def test_trusted_samplebuffer_handoff_emits_plan_and_route_with_snapshot_context(self) -> None:
        controller = (
            REPO_ROOT
            / "PlaybackEngine/Sources/PlaybackEngine/NativePlayer/NativePlayerPlaybackController.swift"
        ).read_text(encoding="utf-8")
        handoff = controller.split("private func makeTrustedNativeHandoffSnapshot", 1)[1].split(
            "private func prepareResolved", 1
        )[0]

        self.assertIn("event: .plan", handoff)
        self.assertIn("event: .routeSelection", handoff)
        self.assertGreaterEqual(handoff.count("session: evidenceContext.session"), 2)
        self.assertGreaterEqual(handoff.count("media: evidenceContext.media"), 2)
        self.assertGreaterEqual(handoff.count("source: evidenceContext.source"), 2)
        self.assertIn("evidenceContext: evidenceContext", handoff)


if __name__ == "__main__":
    unittest.main()
