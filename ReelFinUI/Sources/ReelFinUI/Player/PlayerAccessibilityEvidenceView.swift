import Foundation
import SwiftUI
import UIKit

enum PlayerAccessibilityTransportState: String, Equatable {
    case playing
    case paused
    case buffering
    case failed
    case ended
}

struct PlayerAccessibilityEvidenceState: Equatable {
    static let advancingFreshnessSeconds: TimeInterval = 2.5

    private(set) var isAdvancing = false
    private(set) var didCompleteSeek = false
    private(set) var didCompleteSeekToZero = false
    private(set) var completedSeekTarget: Double?
    private(set) var readerGeneration: Int?

    private var previousPlaybackTime: Double?
    private var advancingObservationCount = 0
    private var pendingSeekTarget: Double?
    private var lastAdvancingObservationAt: TimeInterval?
    private var transportState: PlayerAccessibilityTransportState = .buffering

    var readerGenerationValue: String? { readerGeneration.map(String.init) }

    mutating func observe(playbackTime: Double, generation: Int? = nil) {
        observe(
            playbackTime: playbackTime,
            generation: generation,
            transportState: .playing,
            observedAt: ProcessInfo.processInfo.systemUptime
        )
    }

    mutating func observe(
        playbackTime: Double,
        generation: Int? = nil,
        transportState: PlayerAccessibilityTransportState,
        observedAt: TimeInterval
    ) {
        guard playbackTime.isFinite else { return }
        setTransportState(transportState)
        guard transportState == .playing else { return }
        expireAdvancing(observedAt: observedAt)
        if let generation, generation != readerGeneration {
            readerGeneration = generation
            previousPlaybackTime = nil
            advancingObservationCount = 0
            isAdvancing = false
            lastAdvancingObservationAt = nil
        }

        if let target = pendingSeekTarget,
           abs(max(0, playbackTime) - target) <= 1.25 {
            didCompleteSeek = true
            didCompleteSeekToZero = target <= 0.5
            completedSeekTarget = target
            pendingSeekTarget = nil
        }

        if let previousPlaybackTime {
            if playbackTime - previousPlaybackTime >= 0.35 {
                advancingObservationCount += 1
                isAdvancing = advancingObservationCount >= 2
                if isAdvancing { lastAdvancingObservationAt = observedAt }
            } else if playbackTime < previousPlaybackTime - 0.1 {
                advancingObservationCount = 0
                isAdvancing = false
                lastAdvancingObservationAt = nil
            }
        }
        previousPlaybackTime = playbackTime
    }

    mutating func setTransportState(_ state: PlayerAccessibilityTransportState) {
        transportState = state
        guard state != .playing else { return }
        previousPlaybackTime = nil
        advancingObservationCount = 0
        lastAdvancingObservationAt = nil
        isAdvancing = false
    }

    mutating func expireAdvancing(observedAt: TimeInterval) {
        guard let lastAdvancingObservationAt,
              observedAt - lastAdvancingObservationAt > Self.advancingFreshnessSeconds else { return }
        advancingObservationCount = 0
        isAdvancing = false
        self.lastAdvancingObservationAt = nil
    }

    mutating func beginSeek(target: Double) {
        pendingSeekTarget = max(0, target)
        completedSeekTarget = nil
        didCompleteSeek = false
        didCompleteSeekToZero = false
        previousPlaybackTime = nil
        advancingObservationCount = 0
        lastAdvancingObservationAt = nil
        isAdvancing = false
    }

    mutating func reset() {
        self = Self()
    }
}

struct NativePlayerAccessibilityDiagnostics: Equatable {
    let transportState: PlayerAccessibilityTransportState
    let videoRenderingReady: Bool
    let audioRenderingReady: Bool
    let readerGeneration: Int?

    init(rows: [String]) {
        let state = Self.value(after: "state=", in: rows) ?? "buffering"
        transportState = PlayerAccessibilityTransportState(rawValue: state) ?? .buffering
        let primedVideo = Self.integer(
            named: "video",
            in: Self.row(startingWith: "primed ", in: rows)
        )
        let acceptedVideoPackets = Self.integer(
            named: "video",
            in: Self.row(startingWith: "packets ", in: rows)
        )
        videoRenderingReady = max(primedVideo, acceptedVideoPackets) > 0
        let renderedAudioSamples = Self.integer(
            named: "rendered",
            in: Self.row(startingWith: "audioSamples ", in: rows)
        )
        audioRenderingReady = renderedAudioSamples > 0
        readerGeneration = Self.value(after: "readerGeneration=", in: rows).flatMap(Int.init)
    }

    private static func row(startingWith prefix: String, in rows: [String]) -> String {
        rows.first(where: { $0.hasPrefix(prefix) }) ?? ""
    }

    private static func value(after prefix: String, in rows: [String]) -> String? {
        guard let row = rows.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return String(row.dropFirst(prefix.count).prefix { !$0.isWhitespace })
    }

    private static func integer(named name: String, in row: String) -> Int {
        guard let range = row.range(of: "\(name)=") else { return 0 }
        return Int(row[range.upperBound...].prefix { $0.isNumber }) ?? 0
    }
}

struct PlayerAccessibilityEvidenceView: UIViewRepresentable {
    let playbackTime: Double
    let transportState: PlayerAccessibilityTransportState
    let videoRenderingReady: Bool
    let audioRenderingReady: Bool
    let audioEvidenceRoute: String?
    let isAdvancing: Bool
    let completedSeekTarget: Double?
    let didCompleteSeekToZero: Bool
    let readerGeneration: Int?
    let errorMessage: String?
    var showsLaunchPreparation = false
    var showsBuffering = false

    func makeUIView(context: Context) -> PlayerAccessibilityEvidenceContainerView {
        PlayerAccessibilityEvidenceContainerView()
    }

    func updateUIView(_ view: PlayerAccessibilityEvidenceContainerView, context: Context) {
        view.update(
            playbackTime: playbackTime,
            transportState: transportState,
            videoRenderingReady: videoRenderingReady,
            audioRenderingReady: audioRenderingReady,
            audioEvidenceRoute: audioEvidenceRoute,
            isAdvancing: isAdvancing,
            completedSeekTarget: completedSeekTarget,
            didCompleteSeekToZero: didCompleteSeekToZero,
            readerGeneration: readerGeneration,
            errorMessage: errorMessage,
            showsLaunchPreparation: showsLaunchPreparation,
            showsBuffering: showsBuffering
        )
    }
}

final class PlayerAccessibilityEvidenceContainerView: UIView {
    private var markers: [String: UIView] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    func update(
        playbackTime: Double,
        transportState: PlayerAccessibilityTransportState,
        videoRenderingReady: Bool,
        audioRenderingReady: Bool,
        audioEvidenceRoute: String?,
        isAdvancing: Bool,
        completedSeekTarget: Double?,
        didCompleteSeekToZero: Bool,
        readerGeneration: Int?,
        errorMessage: String?,
        showsLaunchPreparation: Bool,
        showsBuffering: Bool
    ) {
        setMarker("player_playback_time", value: String(format: "%.3f", max(0, playbackTime)))
        setMarker("player_transport_state", value: transportState.rawValue)
        setMarker("player_video_rendering_ready", enabled: videoRenderingReady)
        setMarker(
            "player_audio_rendering_ready",
            value: audioEvidenceRoute,
            enabled: audioRenderingReady
        )
        setMarker("player_playback_advancing", enabled: isAdvancing)
        setMarker(
            "player_seek_completed",
            value: completedSeekTarget.map { String(format: "%.3f", $0) },
            enabled: completedSeekTarget != nil
        )
        setMarker("player_seek_target_zero", enabled: didCompleteSeekToZero)
        setMarker(
            "native_player_reader_generation",
            value: readerGeneration.map(String.init),
            enabled: readerGeneration != nil
        )
        setMarker("player_error", value: errorMessage, enabled: errorMessage != nil)
        setMarker("custom_player_launch_preparation", enabled: showsLaunchPreparation)
        setMarker("custom_player_buffering", enabled: showsBuffering)
    }

    private func setMarker(
        _ identifier: String,
        value: String? = nil,
        enabled: Bool = true
    ) {
        if !enabled {
            markers.removeValue(forKey: identifier)?.removeFromSuperview()
            return
        }
        let marker = markers[identifier] ?? makeMarker(identifier: identifier)
        marker.accessibilityValue = value
    }

    private func makeMarker(identifier: String) -> UIView {
        let marker = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        marker.isAccessibilityElement = true
        marker.accessibilityIdentifier = identifier
        marker.accessibilityLabel = identifier
        marker.isUserInteractionEnabled = false
        marker.backgroundColor = .clear
        addSubview(marker)
        markers[identifier] = marker
        return marker
    }
}

struct PlayerAccessibilityMarkerView: UIViewRepresentable {
    let identifier: String
    var value: String? = nil

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isAccessibilityElement = true
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = identifier
        view.accessibilityValue = value
    }
}
