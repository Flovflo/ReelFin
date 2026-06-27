#!/usr/bin/env python3
"""Fail ReelFin player E2E when logs lack continuous playback evidence."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass, field
from pathlib import Path


KEY_VALUE_RE = re.compile(r"\b([A-Za-z][A-Za-z0-9_]*)=('[^']*'|\"[^\"]*\"|[^\s]+)")
SECRET_URL_RE = re.compile(r"https?://\S+")
SECRET_API_KEY_RE = re.compile(
    r"(?i)\bapi_key=(?!(?:REDACTED|<redacted>|%3Credacted%3E)(?:\b|&))[^&\s]+"
)


@dataclass(frozen=True)
class RequiredAVPlayerItem:
    item_id: str
    min_observed_seconds: float
    min_ticks: int = 3
    require_dv: bool = False
    require_hdr: bool = False

    @property
    def label(self) -> str:
        return short_item_id(self.item_id)


@dataclass(frozen=True)
class EvidenceConfig:
    min_observed_seconds: float = 20.0
    min_ticks: int = 3
    require_dv: bool = False
    require_samplebuffer: bool = False
    required_avplayer_items: tuple[RequiredAVPlayerItem, ...] = ()


@dataclass(frozen=True)
class Finding:
    label: str
    message: str


@dataclass
class AVPlayerSessionEvidence:
    session_id: str
    item_id: str | None = None
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
    rebuffer_waits: int = 0
    rebuffer_ready: int = 0
    rebuffer_timeout: int = 0

    @property
    def observed_seconds(self) -> float:
        if len(self.ticks) < 2:
            return 0.0
        return max(self.ticks) - min(self.ticks)

    @property
    def has_audio(self) -> bool:
        if self.audio_codec is None:
            return False
        return self.audio_codec.lower() not in {"", "none", "unknown", "n/a"}

    @property
    def has_dv(self) -> bool:
        return self.proof_dv

    @property
    def has_proof(self) -> bool:
        return self.proof_method is not None

    @property
    def unresolved_rebuffer_waits(self) -> int:
        return max(0, self.rebuffer_waits - self.rebuffer_ready)

    @property
    def has_hdr(self) -> bool:
        return (self.proof_hdr or "").lower() not in {"", "unknown", "sdr", "n/a", "none"}


@dataclass
class SampleBufferEvidence:
    has_route: bool = False
    has_plan: bool = False
    has_benchmark_contract: bool = False
    tick_count: int = 0
    has_video_packets: bool = False
    has_audio_packets: bool = False
    has_audio_renderer: bool = False
    audio_underruns: int = 0
    audio_rebuffers: int = 0

    @property
    def has_audio(self) -> bool:
        return self.has_audio_packets and self.has_audio_renderer

    @property
    def is_complete(self) -> bool:
        return (
            self.has_route
            and self.has_plan
            and self.has_benchmark_contract
            and self.tick_count > 0
            and self.has_video_packets
            and self.has_audio
            and self.audio_underruns == 0
            and self.audio_rebuffers == 0
        )


@dataclass
class EvidenceResult:
    findings: list[Finding]
    avplayer_sessions: dict[str, AVPlayerSessionEvidence]
    samplebuffer: SampleBufferEvidence

    @property
    def avplayer_session_count(self) -> int:
        return len([session for session in self.avplayer_sessions.values() if session.ticks])

    @property
    def samplebuffer_tick_count(self) -> int:
        return self.samplebuffer.tick_count

    def finding_labels(self) -> list[str]:
        return [finding.label for finding in self.findings]


def redact_sensitive(text: str) -> str:
    text = SECRET_API_KEY_RE.sub("api_key=<redacted>", text)
    return SECRET_URL_RE.sub("<redacted-url>", text)


def short_item_id(value: str | None) -> str:
    return (value or "")[:8]


def matches_item(observed: str | None, expected: str) -> bool:
    if not observed:
        return False
    return observed == expected or observed == short_item_id(expected) or short_item_id(observed) == short_item_id(expected)


def strip_quotes(value: str | None) -> str | None:
    if value is None:
        return None
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def parse_key_values(line: str) -> dict[str, str]:
    return {key: strip_quotes(value) or "" for key, value in KEY_VALUE_RE.findall(line)}


def parse_float(value: str | None) -> float | None:
    if value is None:
        return None
    try:
        parsed = float(value)
    except ValueError:
        return None
    return parsed if parsed == parsed and parsed not in {float("inf"), float("-inf")} else None


def parse_int(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        return int(float(value))
    except ValueError:
        return None


def truthy(value: str | None) -> bool:
    return (value or "").lower() in {"true", "1", "yes"}


def iter_log_files(paths: list[Path]) -> list[Path]:
    files: list[Path] = []
    for path in paths:
        if path.is_file():
            files.append(path)
        elif path.is_dir():
            files.extend(sorted(path.rglob("*.log")))
            files.extend(sorted(path.rglob("*.stream")))
    return [file for file in files if file.name != "deep-playback-evidence.log"]


def update_avplayer_session(
    sessions: dict[str, AVPlayerSessionEvidence],
    line: str,
) -> None:
    fields = parse_key_values(line)
    session_id = fields.get("session")
    if session_id is None:
        return

    session = sessions.setdefault(session_id, AVPlayerSessionEvidence(session_id=session_id))
    session.item_id = fields.get("item") or session.item_id

    if "avplayer.first-frame" in line:
        session.has_first_frame = True
    elif "playback.ttff" in line:
        session.has_ttff = True
    elif "playback.audio.selection" in line:
        session.audio_codec = fields.get("codec") or session.audio_codec
    elif "playback.proof" in line:
        session.proof_dv = truthy(fields.get("dv")) or session.proof_dv
        session.proof_hdr = fields.get("hdr") or session.proof_hdr
        session.proof_method = fields.get("method") or session.proof_method
    elif "playback.deep.tick" in line:
        current = parse_float(fields.get("current"))
        if current is not None:
            session.ticks.append(current)
        session.audio_codec = fields.get("audioCodec") or session.audio_codec
        buffered = parse_float(fields.get("buffered"))
        rate = parse_float(fields.get("rate"))
        time_control = (fields.get("timeControl") or "").lower()
        if buffered is not None and buffered <= 0.05:
            session.zero_buffer_ticks += 1
        if time_control == "waiting":
            session.waiting_ticks += 1
        if time_control == "waiting" or ((rate or 0) <= 0 and buffered is not None and buffered <= 0.05):
            session.stalled_ticks += 1
    elif "playback.directplay.poststart_rebuffer.wait" in line:
        session.rebuffer_waits += 1
    elif "playback.directplay.poststart_rebuffer.ready" in line:
        session.rebuffer_ready += 1
    elif "playback.directplay.poststart_rebuffer.timeout" in line:
        session.rebuffer_timeout += 1


def update_samplebuffer_evidence(samplebuffer: SampleBufferEvidence, line: str) -> None:
    fields = parse_key_values(line)
    if "nativeplayer.sampleBuffer.route.selected" in line:
        samplebuffer.has_route = True
        return

    if "nativeplayer.playbackPlan.created" in line:
        video = (fields.get("video") or "").lower()
        audio = (fields.get("audio") or "").lower()
        can_start = truthy(fields.get("canStart"))
        samplebuffer.has_plan = samplebuffer.has_plan or (
            can_start
            and video not in {"", "none", "missing", "unavailable"}
            and audio not in {"", "none", "missing", "unavailable"}
        )
        return

    if "NativeEngine+AVSampleBufferDisplayLayer" in line and "mkv_original" in line and "PASS" in line:
        audio_match = re.search(r"\baudio=([^\s]+)", line)
        audio = audio_match.group(1).lower() if audio_match else ""
        samplebuffer.has_benchmark_contract = audio not in {"", "unknown", "none", "n/a"}
        return

    if "nativeplayer.deep.tick" not in line:
        return

    samplebuffer.tick_count += 1
    video_packets = parse_int(fields.get("videoPackets"))
    audio_packets = parse_int(fields.get("audioPackets"))
    audio_samples = parse_int(fields.get("audioSamples"))
    audio_renderer = (fields.get("audioRenderer") or "").lower()
    samplebuffer.has_video_packets = samplebuffer.has_video_packets or (video_packets or 0) > 0
    samplebuffer.has_audio_packets = samplebuffer.has_audio_packets or (audio_packets or 0) > 0 or (audio_samples or 0) > 0
    samplebuffer.has_audio_renderer = samplebuffer.has_audio_renderer or "avsamplebufferaudiorenderer" in audio_renderer
    samplebuffer.audio_underruns += parse_int(fields.get("audioUnderruns")) or 0
    samplebuffer.audio_rebuffers += parse_int(fields.get("audioRebuffers")) or 0


def scan_files(paths: list[Path]) -> tuple[dict[str, AVPlayerSessionEvidence], SampleBufferEvidence, list[Finding]]:
    sessions: dict[str, AVPlayerSessionEvidence] = {}
    samplebuffer = SampleBufferEvidence()
    findings: list[Finding] = []

    for log_file in iter_log_files(paths):
        try:
            lines = log_file.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError as error:
            findings.append(Finding("read_error", f"{log_file}: {error}"))
            continue

        for line_number, line in enumerate(lines, start=1):
            try:
                if "Playback stalled." in line:
                    findings.append(Finding("runtime_playback_stalled", f"{log_file}:{line_number}: {redact_sensitive(line.strip())}"))

                if (
                    "avplayer.first-frame" in line
                    or "playback.ttff" in line
                    or "playback.audio.selection" in line
                    or "playback.proof" in line
                    or "playback.deep.tick" in line
                    or "playback.directplay.poststart_rebuffer." in line
                ):
                    update_avplayer_session(sessions, line)
                update_samplebuffer_evidence(samplebuffer, line)
            except Exception as error:  # pragma: no cover - defensive log parser guard.
                findings.append(
                    Finding(
                        "parse_error",
                        f"{log_file}:{line_number}: {error}: {redact_sensitive(line.strip())}",
                    )
                )

    return sessions, samplebuffer, findings


def validate_avplayer_session(
    session: AVPlayerSessionEvidence,
    min_observed_seconds: float,
    min_ticks: int,
    require_dv: bool,
    require_hdr: bool,
    label_prefix: str,
    item_label: str | None = None,
) -> Finding | None:
    subject = item_label or session.session_id
    if not session.has_first_frame or not session.has_ttff:
        return Finding(
            f"{label_prefix}_startup_evidence_incomplete",
            f"AVPlayer session {session.session_id} for {subject} lacks first-frame or TTFF evidence.",
        )
    if not session.has_audio:
        return Finding(
            f"{label_prefix}_audio_evidence_missing",
            f"AVPlayer session {session.session_id} for {subject} has no concrete audio codec selection.",
        )
    if not session.has_proof:
        return Finding(
            f"{label_prefix}_playback_proof_missing",
            f"AVPlayer session {session.session_id} for {subject} has no playback.proof line.",
        )
    if require_dv and not session.has_dv:
        return Finding(
            f"{label_prefix}_dolby_vision_evidence_missing",
            f"AVPlayer session {session.session_id} for {subject} did not report dv=true.",
        )
    if require_hdr and not session.has_hdr:
        return Finding(
            f"{label_prefix}_hdr_evidence_missing",
            f"AVPlayer session {session.session_id} for {subject} did not report HDR evidence.",
        )
    if len(session.ticks) < min_ticks:
        return Finding(
            f"{label_prefix}_deep_ticks_below_minimum",
            f"AVPlayer session {session.session_id} for {subject} has {len(session.ticks)} ticks; need {min_ticks}.",
        )
    if session.observed_seconds < min_observed_seconds:
        return Finding(
            f"{label_prefix}_observed_progress_below_minimum",
            f"AVPlayer session {session.session_id} for {subject} advanced {session.observed_seconds:.1f}s; need {min_observed_seconds:.1f}s.",
        )
    if session.rebuffer_timeout > 0:
        return Finding(
            f"{label_prefix}_poststart_rebuffer_timeout",
            f"AVPlayer session {session.session_id} for {subject} hit {session.rebuffer_timeout} post-start rebuffer timeout(s).",
        )
    if session.unresolved_rebuffer_waits > 0:
        return Finding(
            f"{label_prefix}_poststart_rebuffer_unresolved",
            f"AVPlayer session {session.session_id} for {subject} has {session.unresolved_rebuffer_waits} post-start rebuffer wait(s) without ready recovery.",
        )
    if session.stalled_ticks >= 2:
        return Finding(
            f"{label_prefix}_stalled_ticks",
            f"AVPlayer session {session.session_id} for {subject} reported {session.stalled_ticks} waiting/zero-buffer deep tick(s).",
        )
    if session.zero_buffer_ticks >= 2:
        return Finding(
            f"{label_prefix}_zero_buffer_ticks",
            f"AVPlayer session {session.session_id} for {subject} reported {session.zero_buffer_ticks} zero-buffer deep tick(s).",
        )
    return None


def validate_required_avplayer_item(
    sessions: dict[str, AVPlayerSessionEvidence],
    requirement: RequiredAVPlayerItem,
) -> Finding | None:
    matching = [
        session for session in sessions.values()
        if matches_item(session.item_id, requirement.item_id)
    ]
    if not matching:
        return Finding(
            "required_avplayer_session_missing",
            f"No AVPlayer evidence found for required item {requirement.label}.",
        )

    candidates = sorted(
        matching,
        key=lambda session: (
            session.observed_seconds,
            len(session.ticks),
            session.has_first_frame,
            session.has_ttff,
            session.has_audio,
            session.has_dv,
        ),
        reverse=True,
    )
    best_failure: Finding | None = None
    for session in candidates:
        failure = validate_avplayer_session(
            session,
            min_observed_seconds=requirement.min_observed_seconds,
            min_ticks=requirement.min_ticks,
            require_dv=requirement.require_dv,
            require_hdr=requirement.require_hdr,
            label_prefix="required_avplayer",
            item_label=requirement.label,
        )
        if failure is None:
            return None
        best_failure = best_failure or failure
    return best_failure


def evaluate_paths(paths: list[Path], config: EvidenceConfig) -> EvidenceResult:
    sessions, samplebuffer, findings = scan_files(paths)
    playable_sessions = [
        session for session in sessions.values()
        if session.has_first_frame or session.has_ttff or session.ticks
    ]

    for session in playable_sessions:
        if session.rebuffer_timeout > 0:
            findings.append(
                Finding(
                    "avplayer_poststart_rebuffer_timeout",
                    f"AVPlayer session {session.session_id} hit {session.rebuffer_timeout} post-start rebuffer timeout(s).",
                )
            )
        elif session.unresolved_rebuffer_waits > 0:
            findings.append(
                Finding(
                    "avplayer_poststart_rebuffer_unresolved",
                    f"AVPlayer session {session.session_id} has {session.unresolved_rebuffer_waits} post-start rebuffer wait(s) without ready recovery.",
                )
            )

    for requirement in config.required_avplayer_items:
        failure = validate_required_avplayer_item(sessions, requirement)
        if failure is not None:
            findings.append(failure)

    if not playable_sessions:
        findings.append(Finding("avplayer_session_evidence_missing", "No AVPlayer first-frame/TTFF/tick evidence found."))
    elif not config.required_avplayer_items:
        valid_session = False
        tickiest_session = max(playable_sessions, key=lambda session: len(session.ticks))
        for session in playable_sessions:
            if validate_avplayer_session(
                session,
                min_observed_seconds=config.min_observed_seconds,
                min_ticks=config.min_ticks,
                require_dv=False,
                require_hdr=False,
                label_prefix="avplayer",
            ) is None:
                valid_session = True
                break

        if not valid_session:
            if len(tickiest_session.ticks) < config.min_ticks:
                findings.append(
                    Finding(
                        "avplayer_deep_ticks_below_minimum",
                        f"Best AVPlayer session {tickiest_session.session_id} has {len(tickiest_session.ticks)} ticks; need {config.min_ticks}.",
                    )
                )
            elif tickiest_session.observed_seconds < config.min_observed_seconds:
                findings.append(
                    Finding(
                        "avplayer_observed_progress_below_minimum",
                        f"Best AVPlayer session {tickiest_session.session_id} advanced {tickiest_session.observed_seconds:.1f}s; need {config.min_observed_seconds:.1f}s.",
                    )
                )
            elif not tickiest_session.has_audio:
                findings.append(
                    Finding(
                        "avplayer_audio_evidence_missing",
                        f"Best AVPlayer session {tickiest_session.session_id} has no concrete audio codec selection.",
                    )
                )
            elif not tickiest_session.has_proof:
                findings.append(
                    Finding(
                        "avplayer_playback_proof_missing",
                        f"Best AVPlayer session {tickiest_session.session_id} has no playback.proof line.",
                    )
                )
            else:
                findings.append(
                    Finding(
                        "avplayer_startup_evidence_incomplete",
                        f"Best AVPlayer session {tickiest_session.session_id} lacks first-frame or TTFF evidence.",
                    )
                )

    if config.require_dv and not any(session.has_dv for session in sessions.values()):
        findings.append(Finding("dolby_vision_evidence_missing", "No playback.proof line reported dv=true."))

    if config.require_samplebuffer:
        if not samplebuffer.has_route:
            findings.append(Finding("samplebuffer_route_evidence_missing", "No nativeplayer.sampleBuffer.route.selected line found."))
        if not samplebuffer.has_plan:
            findings.append(Finding("samplebuffer_plan_evidence_missing", "No successful nativeplayer.playbackPlan.created line with video and audio backends found."))
        if not samplebuffer.has_benchmark_contract:
            findings.append(Finding("samplebuffer_benchmark_contract_missing", "No mkv_original NativeEngine+AVSampleBufferDisplayLayer benchmark pass with audio codec found."))
        if samplebuffer.tick_count == 0:
            findings.append(Finding("samplebuffer_deep_tick_missing", "No nativeplayer.deep.tick line found."))
        if samplebuffer.tick_count > 0 and not samplebuffer.has_video_packets:
            findings.append(Finding("samplebuffer_video_packet_evidence_missing", "Sample-buffer ticks did not report video packets."))
        if samplebuffer.tick_count > 0 and not samplebuffer.has_audio:
            findings.append(Finding("samplebuffer_audio_evidence_missing", "Sample-buffer ticks did not report audio packets/samples and renderer."))
        if samplebuffer.audio_underruns > 0:
            findings.append(Finding("samplebuffer_audio_underrun", f"Sample-buffer audio underruns: {samplebuffer.audio_underruns}."))
        if samplebuffer.audio_rebuffers > 0:
            findings.append(Finding("samplebuffer_audio_rebuffer", f"Sample-buffer audio rebuffers: {samplebuffer.audio_rebuffers}."))

    return EvidenceResult(findings=findings, avplayer_sessions=sessions, samplebuffer=samplebuffer)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate ReelFin deep player evidence from live E2E logs.")
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--min-observed-seconds", type=float, default=20.0)
    parser.add_argument("--min-ticks", type=int, default=3)
    parser.add_argument("--require-dv", action="store_true")
    parser.add_argument("--require-samplebuffer", action="store_true")
    parser.add_argument(
        "--require-avplayer-item",
        action="append",
        default=[],
        metavar="ITEM[:SECONDS[:TICKS[:DV[:HDR]]]]",
        help="Require AVPlayer evidence for a specific item. ITEM may be full or short id.",
    )
    args = parser.parse_args()

    required_avplayer_items = tuple(
        parse_required_avplayer_item(spec, args.min_observed_seconds, args.min_ticks)
        for spec in args.require_avplayer_item
    )

    result = evaluate_paths(
        args.paths,
        EvidenceConfig(
            min_observed_seconds=args.min_observed_seconds,
            min_ticks=args.min_ticks,
            require_dv=args.require_dv,
            require_samplebuffer=args.require_samplebuffer,
            required_avplayer_items=required_avplayer_items,
        ),
    )

    if result.findings:
        print("FAIL player deep playback evidence")
        for finding in result.findings:
            print(f"  - {finding.label}: {redact_sensitive(finding.message)}")
        return 1

    best_progress = 0.0
    if result.avplayer_sessions:
        best_progress = max(session.observed_seconds for session in result.avplayer_sessions.values())
    print(
        "PASS player deep playback evidence "
        f"avplayerSessions={result.avplayer_session_count} "
        f"bestProgress={best_progress:.1f}s "
        f"sampleBufferTicks={result.samplebuffer_tick_count}"
    )
    return 0


def parse_required_avplayer_item(
    spec: str,
    default_min_observed_seconds: float,
    default_min_ticks: int,
) -> RequiredAVPlayerItem:
    parts = spec.split(":")
    item_id = parts[0].strip()
    if not item_id:
        raise argparse.ArgumentTypeError("--require-avplayer-item needs a non-empty item id")
    min_seconds = default_min_observed_seconds
    min_ticks = default_min_ticks
    require_dv = False
    require_hdr = False
    if len(parts) > 1 and parts[1]:
        min_seconds = float(parts[1])
    if len(parts) > 2 and parts[2]:
        min_ticks = int(parts[2])
    if len(parts) > 3 and parts[3]:
        require_dv = truthy(parts[3])
    if len(parts) > 4 and parts[4]:
        require_hdr = truthy(parts[4])
    return RequiredAVPlayerItem(
        item_id=item_id,
        min_observed_seconds=min_seconds,
        min_ticks=min_ticks,
        require_dv=require_dv,
        require_hdr=require_hdr,
    )


if __name__ == "__main__":
    raise SystemExit(main())
