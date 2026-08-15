"""Validate ReelFin's typed, opaque deep playback JSONL evidence."""

from __future__ import annotations

import argparse
import json
import math
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


OPAQUE_CORRELATION_RE = re.compile(r"^[0-9a-f]{16}$")
SECRET_URL_RE = re.compile(r"https?://\S+")
SECRET_API_KEY_RE = re.compile(
    r"(?i)\bapi_key=(?!(?:REDACTED|<redacted>|%3Credacted%3E)(?:\b|&))[^&\s]+"
)

EVENT_FIELDS: dict[str, dict[str, type | tuple[type, ...]]] = {
    "plan": {
        "canStart": bool,
        "demuxer": str,
        "videoBackend": str,
        "audioBackend": str,
    },
    "routeSelection": {
        "route": str,
        "avPlayerItem": bool,
        "avPlayerViewController": bool,
        "serverTranscodeUsed": bool,
    },
    "audioSelection": {"codec": str, "isDefault": bool},
    "firstFrame": {"elapsedMilliseconds": (int, float), "currentSeconds": (int, float)},
    "ttff": {
        "totalMilliseconds": (int, float),
        "infoMilliseconds": (int, float),
        "resolveMilliseconds": (int, float),
        "readyMilliseconds": (int, float),
        "playerMilliseconds": (int, float),
        "method": str,
        "profile": str,
        "route": str,
        "videoIntegrity": str,
        "hdrIntegrity": str,
    },
    "avPlayerTick": {
        "currentSeconds": (int, float),
        "deltaSeconds": (int, float),
        "rate": (int, float),
        "timeControl": str,
        "itemStatus": str,
        "likelyToKeepUp": bool,
        "bufferedSeconds": (int, float),
        "droppedFrames": int,
        "observedBitrate": int,
        "accessObservedBitrate": int,
        "accessIndicatedBitrate": int,
        "accessStalls": int,
        "accessTransferSeconds": (int, float),
        "codec": str,
        "method": str,
    },
    "playbackProof": {
        "width": int,
        "height": int,
        "codec": str,
        "bitDepth": int,
        "hdr": str,
        "dolbyVision": bool,
        "method": str,
        "profile": str,
        "sourceBitrate": int,
        "container": str,
        "dolbyVisionProfile": int,
        "dolbyVisionLevel": int,
        "videoRange": str,
        "observedBitrate": int,
    },
    "sampleBufferTick": {
        "currentSeconds": (int, float),
        "deltaSeconds": (int, float),
        "state": str,
        "videoPackets": int,
        "audioPackets": int,
        "audioSamples": int,
        "audioRenderer": str,
        "droppedFrames": int,
        "audioUnderruns": int,
        "audioRebuffers": int,
        "avDriftMilliseconds": (int, float),
        "hdr": str,
        "dolbyVisionProfile": int,
    },
}

CATEGORIES = {
    "unknown", "none", "directPlay", "directStream", "transcode", "native",
    "avPlayer", "sampleBuffer", "matroska", "mp4", "mpegts", "videoToolbox",
    "sampleBufferAudioRenderer", "hevc", "hvc1", "h264", "avc1", "eac3",
    "ac3", "aac", "truehd", "opus", "flac", "playing", "paused", "waiting",
    "readyToPlay", "failed", "pq", "hlg", "sdr", "hdr10", "dolbyVision",
    "originalVideo", "originalHDR", "watchableSDR", "preserved", "converted",
    "unavailable",
}

COMMON_FIELDS = {"event", "session", "media", "source", "timestampMilliseconds"}


@dataclass(frozen=True)
class RequiredAVPlayerScenario:
    scenario: str
    min_observed_seconds: float
    min_ticks: int = 3
    require_dv: bool = False
    require_hdr: bool = False


@dataclass(frozen=True)
class EvidenceConfig:
    min_observed_seconds: float = 20.0
    min_ticks: int = 3
    require_dv: bool = False
    require_samplebuffer: bool = False
    required_avplayer_scenarios: tuple[RequiredAVPlayerScenario, ...] = ()


@dataclass(frozen=True)
class Finding:
    label: str
    message: str


@dataclass
class AVPlayerSessionEvidence:
    scenario: str
    session_id: str
    media_correlation: str
    has_first_frame: bool = False
    has_ttff: bool = False
    audio_codec: str | None = None
    proof_dv: bool = False
    proof_hdr: str | None = None
    proof_method: str | None = None
    ticks: list[float] = field(default_factory=list)
    waiting_ticks: int = 0
    zero_buffer_ticks: int = 0
    stalled_ticks: int = 0

    @property
    def observed_seconds(self) -> float:
        return max(self.ticks) - min(self.ticks) if len(self.ticks) >= 2 else 0.0

    @property
    def has_audio(self) -> bool:
        return (self.audio_codec or "") not in {"", "none", "unknown", "unavailable"}

    @property
    def has_hdr(self) -> bool:
        return (self.proof_hdr or "") not in {"", "none", "unknown", "sdr", "unavailable"}


@dataclass
class SampleBufferEvidence:
    scenario: str
    session_id: str
    media_correlation: str
    source_correlation: str
    has_plan: bool = False
    has_route: bool = False
    tick_count: int = 0
    has_video_packets: bool = False
    has_audio_packets: bool = False
    has_audio_renderer: bool = False
    audio_underruns: int = 0
    audio_rebuffers: int = 0

    @property
    def has_plan_and_route(self) -> bool:
        return self.has_plan and self.has_route

    @property
    def has_audio(self) -> bool:
        return self.has_audio_packets and self.has_audio_renderer


@dataclass
class EvidenceResult:
    findings: list[Finding]
    avplayer_sessions: dict[str, AVPlayerSessionEvidence]
    samplebuffer_sessions: dict[str, SampleBufferEvidence]

    @property
    def avplayer_session_count(self) -> int:
        return len([session for session in self.avplayer_sessions.values() if session.ticks])

    @property
    def samplebuffer_tick_count(self) -> int:
        return sum(session.tick_count for session in self.samplebuffer_sessions.values())

    def finding_labels(self) -> list[str]:
        return [finding.label for finding in self.findings]


def redact_sensitive(text: str) -> str:
    text = SECRET_API_KEY_RE.sub("api_key=<redacted>", text)
    return SECRET_URL_RE.sub("<redacted-url>", text)


def truthy(value: str | None) -> bool:
    return (value or "").lower() in {"true", "1", "yes"}


def scenario_for_file(path: Path) -> str:
    name = path.name.lower()
    if "hdr-dv-long" in name:
        return "directplay-hdr-dv-long"
    if "samplebuffer" in name:
        return "samplebuffer-mkv"
    if name == "ios-live-ui-runtime.stream" or "directplay-mp4" in name:
        return "directplay-mp4"
    return path.stem


def iter_log_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            files.extend(sorted(path.rglob("*.log")))
            files.extend(sorted(path.rglob("*.stream")))
            files.extend(sorted(path.rglob("*.jsonl")))
    return [file for file in files if file.name != "deep-playback-evidence.log"]


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def valid_typed_record(record: object) -> bool:
    if not isinstance(record, dict):
        return False
    event = record.get("event")
    session = record.get("session")
    media = record.get("media")
    source = record.get("source")
    if event not in EVENT_FIELDS or not isinstance(session, str) or not OPAQUE_CORRELATION_RE.fullmatch(session):
        return False
    for correlation in (media, source):
        if correlation is not None and (
            not isinstance(correlation, str) or not OPAQUE_CORRELATION_RE.fullmatch(correlation)
        ):
            return False
    if "timestampMilliseconds" in record and not isinstance(record["timestampMilliseconds"], int):
        return False
    allowed_fields = EVENT_FIELDS[event]
    if not set(record).issubset(COMMON_FIELDS.union(allowed_fields)):
        return False
    for name, value in record.items():
        if name in COMMON_FIELDS:
            continue
        expected = allowed_fields[name]
        if expected in {(int, float), (float, int)}:
            if not is_number(value):
                return False
        elif expected is int:
            if not isinstance(value, int) or isinstance(value, bool):
                return False
        elif not isinstance(value, expected):
            return False
        if expected is str and value not in CATEGORIES:
            return False
    return True


def update_avplayer(
    sessions: dict[str, AVPlayerSessionEvidence],
    scenario: str,
    record: dict[str, Any],
) -> None:
    media = record.get("media")
    if not isinstance(media, str):
        return
    session_id = record["session"]
    key = f"{scenario}:{session_id}:{media}"
    session = sessions.setdefault(key, AVPlayerSessionEvidence(scenario, session_id, media))
    event = record["event"]
    if event == "firstFrame":
        session.has_first_frame = True
    elif event == "ttff":
        session.has_ttff = True
    elif event == "audioSelection":
        session.audio_codec = record.get("codec") or session.audio_codec
    elif event == "playbackProof":
        session.proof_dv = bool(record.get("dolbyVision")) or session.proof_dv
        session.proof_hdr = record.get("hdr") or session.proof_hdr
        session.proof_method = record.get("method") or session.proof_method
    elif event == "avPlayerTick":
        current = record.get("currentSeconds")
        if is_number(current):
            session.ticks.append(float(current))
        session.audio_codec = record.get("codec") or session.audio_codec
        buffered = record.get("bufferedSeconds")
        rate = record.get("rate")
        waiting = record.get("timeControl") == "waiting"
        zero_buffer = is_number(buffered) and float(buffered) <= 0.05
        if waiting:
            session.waiting_ticks += 1
        if zero_buffer:
            session.zero_buffer_ticks += 1
        if waiting or (is_number(rate) and float(rate) <= 0 and zero_buffer):
            session.stalled_ticks += 1


def update_samplebuffer(
    sessions: dict[str, SampleBufferEvidence],
    scenario: str,
    record: dict[str, Any],
) -> None:
    media = record.get("media")
    source = record.get("source")
    if not isinstance(media, str) or not isinstance(source, str):
        return
    session_id = record["session"]
    key = f"{scenario}:{session_id}:{media}:{source}"
    evidence = sessions.setdefault(key, SampleBufferEvidence(scenario, session_id, media, source))
    event = record["event"]
    if event == "plan" and record.get("canStart") is True:
        video = record.get("videoBackend")
        audio = record.get("audioBackend")
        if video not in {None, "none", "unknown", "unavailable"} and audio not in {None, "none", "unknown", "unavailable"}:
            evidence.has_plan = True
    elif event == "routeSelection" and record.get("route") == "sampleBuffer":
        evidence.has_route = True
    elif event == "sampleBufferTick":
        evidence.tick_count += 1
        evidence.has_video_packets |= int(record.get("videoPackets", 0)) > 0
        evidence.has_audio_packets |= int(record.get("audioPackets", 0)) > 0 or int(record.get("audioSamples", 0)) > 0
        evidence.has_audio_renderer |= record.get("audioRenderer") == "sampleBufferAudioRenderer"
        evidence.audio_underruns += int(record.get("audioUnderruns", 0))
        evidence.audio_rebuffers += int(record.get("audioRebuffers", 0))


def scan_files(
    paths: list[Path],
) -> tuple[dict[str, AVPlayerSessionEvidence], dict[str, SampleBufferEvidence], bool, list[Finding]]:
    avplayer: dict[str, AVPlayerSessionEvidence] = {}
    samplebuffer: dict[str, SampleBufferEvidence] = {}
    benchmark_contract = False
    findings: list[Finding] = []
    for log_file in iter_log_files(paths):
        scenario = scenario_for_file(log_file)
        try:
            lines = log_file.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            findings.append(Finding("read_error", f"{log_file}: evidence file could not be read"))
            continue
        for line_number, line in enumerate(lines, start=1):
            if "NativeEngine+AVSampleBufferDisplayLayer" in line and "mkv_original" in line and "PASS" in line:
                benchmark_contract = "audio=unknown" not in line and "audio=none" not in line
            stripped = line.strip()
            if not stripped.startswith("{"):
                continue
            try:
                record = json.loads(stripped)
            except json.JSONDecodeError:
                findings.append(Finding("invalid_deep_evidence_schema", f"{log_file}:{line_number}: rejected typed evidence record"))
                continue
            if not valid_typed_record(record):
                findings.append(Finding("invalid_deep_evidence_schema", f"{log_file}:{line_number}: rejected typed evidence record"))
                continue
            update_avplayer(avplayer, scenario, record)
            update_samplebuffer(samplebuffer, scenario, record)
    return avplayer, samplebuffer, benchmark_contract, findings


def validate_avplayer_session(
    session: AVPlayerSessionEvidence,
    min_observed_seconds: float,
    min_ticks: int,
    require_dv: bool,
    require_hdr: bool,
    label_prefix: str,
) -> Finding | None:
    subject = f"scenario {session.scenario} session {session.session_id} media {session.media_correlation}"
    if not session.has_first_frame or not session.has_ttff:
        return Finding(f"{label_prefix}_startup_evidence_incomplete", f"{subject} lacks first-frame or TTFF evidence")
    if not session.has_audio:
        return Finding(f"{label_prefix}_audio_evidence_missing", f"{subject} has no concrete audio codec")
    if session.proof_method is None:
        return Finding(f"{label_prefix}_playback_proof_missing", f"{subject} lacks playback proof")
    if require_dv and not session.proof_dv:
        return Finding(f"{label_prefix}_dolby_vision_evidence_missing", f"{subject} did not report Dolby Vision")
    if require_hdr and not session.has_hdr:
        return Finding(f"{label_prefix}_hdr_evidence_missing", f"{subject} did not report HDR")
    if len(session.ticks) < min_ticks:
        return Finding(f"{label_prefix}_deep_ticks_below_minimum", f"{subject} has {len(session.ticks)} ticks; need {min_ticks}")
    if session.observed_seconds < min_observed_seconds:
        return Finding(f"{label_prefix}_observed_progress_below_minimum", f"{subject} advanced {session.observed_seconds:.1f}s; need {min_observed_seconds:.1f}s")
    if session.stalled_ticks >= 2:
        return Finding(f"{label_prefix}_stalled_ticks", f"{subject} reported {session.stalled_ticks} stalled ticks")
    if session.zero_buffer_ticks >= 2:
        return Finding(f"{label_prefix}_zero_buffer_ticks", f"{subject} reported {session.zero_buffer_ticks} zero-buffer ticks")
    return None


def evaluate_paths(paths: list[Path], config: EvidenceConfig) -> EvidenceResult:
    avplayer, samplebuffer, benchmark_contract, findings = scan_files(paths)
    playable = [session for session in avplayer.values() if session.has_first_frame or session.has_ttff or session.ticks]

    for requirement in config.required_avplayer_scenarios:
        candidates = [session for session in playable if session.scenario == requirement.scenario]
        if not candidates:
            findings.append(Finding("required_avplayer_scenario_missing", f"No AVPlayer evidence found for scenario {requirement.scenario}"))
            continue
        failures = [
            validate_avplayer_session(
                session,
                requirement.min_observed_seconds,
                requirement.min_ticks,
                requirement.require_dv,
                requirement.require_hdr,
                "required_avplayer",
            )
            for session in candidates
        ]
        if all(failure is not None for failure in failures):
            findings.append(next(failure for failure in failures if failure is not None))

    if not playable:
        findings.append(Finding("avplayer_session_evidence_missing", "No typed AVPlayer evidence found"))
    elif not config.required_avplayer_scenarios:
        failures = [
            validate_avplayer_session(session, config.min_observed_seconds, config.min_ticks, False, False, "avplayer")
            for session in playable
        ]
        if all(failure is not None for failure in failures):
            findings.append(next(failure for failure in failures if failure is not None))

    if config.require_dv and not any(session.proof_dv for session in playable):
        findings.append(Finding("dolby_vision_evidence_missing", "No typed playback proof reported Dolby Vision"))

    if config.require_samplebuffer:
        complete = [evidence for evidence in samplebuffer.values() if evidence.has_plan_and_route and evidence.tick_count]
        if not complete:
            findings.append(Finding(
                "samplebuffer_correlated_evidence_missing",
                "No scenario/session/media/source has a correlated sample-buffer plan, route, and tick",
            ))
        if not any(evidence.has_plan_and_route for evidence in samplebuffer.values()):
            findings.append(Finding("samplebuffer_plan_route_evidence_missing", "No scenario/session/media/source has a correlated sample-buffer plan and route"))
        if not benchmark_contract:
            findings.append(Finding("samplebuffer_benchmark_contract_missing", "No sample-buffer benchmark contract pass found"))
        if not any(evidence.tick_count for evidence in samplebuffer.values()):
            findings.append(Finding("samplebuffer_deep_tick_missing", "No typed sample-buffer tick found"))
        if complete and not any(evidence.has_video_packets for evidence in complete):
            findings.append(Finding("samplebuffer_video_packet_evidence_missing", "Sample-buffer ticks did not report video packets"))
        if complete and not any(evidence.has_audio for evidence in complete):
            findings.append(Finding("samplebuffer_audio_evidence_missing", "Sample-buffer ticks did not report audio packets/samples and renderer"))
        underruns = sum(evidence.audio_underruns for evidence in complete)
        rebuffers = sum(evidence.audio_rebuffers for evidence in complete)
        if underruns:
            findings.append(Finding("samplebuffer_audio_underrun", f"Sample-buffer audio underruns: {underruns}"))
        if rebuffers:
            findings.append(Finding("samplebuffer_audio_rebuffer", f"Sample-buffer audio rebuffers: {rebuffers}"))

    return EvidenceResult(findings, avplayer, samplebuffer)


def parse_required_avplayer_scenario(
    spec: str,
    default_min_observed_seconds: float,
    default_min_ticks: int,
) -> RequiredAVPlayerScenario:
    parts = spec.split(":")
    scenario = parts[0].strip()
    if not scenario or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", scenario):
        raise argparse.ArgumentTypeError("--require-avplayer-scenario needs a safe scenario label")
    return RequiredAVPlayerScenario(
        scenario=scenario,
        min_observed_seconds=float(parts[1]) if len(parts) > 1 and parts[1] else default_min_observed_seconds,
        min_ticks=int(parts[2]) if len(parts) > 2 and parts[2] else default_min_ticks,
        require_dv=truthy(parts[3]) if len(parts) > 3 else False,
        require_hdr=truthy(parts[4]) if len(parts) > 4 else False,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate ReelFin typed deep player evidence")
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--min-observed-seconds", type=float, default=20.0)
    parser.add_argument("--min-ticks", type=int, default=3)
    parser.add_argument("--require-dv", action="store_true")
    parser.add_argument("--require-samplebuffer", action="store_true")
    parser.add_argument(
        "--require-avplayer-scenario",
        action="append",
        default=[],
        metavar="SCENARIO[:SECONDS[:TICKS[:DV[:HDR]]]]",
    )
    args = parser.parse_args()
    required = tuple(
        parse_required_avplayer_scenario(spec, args.min_observed_seconds, args.min_ticks)
        for spec in args.require_avplayer_scenario
    )
    result = evaluate_paths(
        args.paths,
        EvidenceConfig(
            min_observed_seconds=args.min_observed_seconds,
            min_ticks=args.min_ticks,
            require_dv=args.require_dv,
            require_samplebuffer=args.require_samplebuffer,
            required_avplayer_scenarios=required,
        ),
    )
    if result.findings:
        print("FAIL player deep playback evidence")
        for finding in result.findings:
            print(f"  - {finding.label}: {redact_sensitive(finding.message)}")
        return 1
    best_progress = max((session.observed_seconds for session in result.avplayer_sessions.values()), default=0.0)
    print(
        "PASS player deep playback evidence "
        f"avplayerSessions={result.avplayer_session_count} "
        f"bestProgress={best_progress:.1f}s "
        f"sampleBufferTicks={result.samplebuffer_tick_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
