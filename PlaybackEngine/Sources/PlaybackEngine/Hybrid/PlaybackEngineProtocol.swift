import AVFoundation
import Foundation
import Shared
import SwiftUI

// MARK: - Unified Track Model

/// Engine-agnostic track representation for audio and subtitle tracks.
public struct UnifiedTrack: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let language: String?
    public let codec: String?
    public let isDefault: Bool
    public let index: Int
    public let engineSource: EngineSource

    public enum EngineSource: String, Sendable, Equatable {
        case native
        case vlc
        case server // from Jellyfin metadata
    }

    public init(
        id: String,
        title: String,
        language: String? = nil,
        codec: String? = nil,
        isDefault: Bool = false,
        index: Int,
        engineSource: EngineSource = .server
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.codec = codec
        self.isDefault = isDefault
        self.index = index
        self.engineSource = engineSource
    }

    /// Convert from Jellyfin MediaTrack.
    public static func from(_ track: MediaTrack, engineSource: EngineSource = .server) -> UnifiedTrack {
        UnifiedTrack(
            id: track.id,
            title: track.title,
            language: track.language,
            codec: track.codec,
            isDefault: track.isDefault,
            index: track.index,
            engineSource: engineSource
        )
    }
}

// MARK: - Playback Engine Protocol

/// Unified interface for a playback engine adapter.
/// Both NativeAVPlayerEngine and VLCPlaybackEngine conform to this.
@MainActor
public protocol PlaybackEngineAdapter: AnyObject {
    /// Current playback state.
    var playbackState: UnifiedPlaybackState { get }

    /// Current playback position in seconds.
    var currentTime: TimeInterval { get }

    /// Total duration in seconds (0 if unknown).
    var duration: TimeInterval { get }

    /// Whether the engine is currently buffering.
    var isBuffering: Bool { get }

    /// Current error message, if any.
    var errorMessage: String? { get }

    /// Available audio tracks from the engine.
    var audioTracks: [UnifiedTrack] { get }

    /// Available subtitle tracks from the engine.
    var subtitleTracks: [UnifiedTrack] { get }

    /// Currently selected audio track ID.
    var selectedAudioTrackID: String? { get }

    /// Currently selected subtitle track ID (nil = disabled).
    var selectedSubtitleTrackID: String? { get }

    /// Whether the engine is playing content.
    var isPlaying: Bool { get }

    /// Prepare and load a URL for playback.
    func prepare(url: URL, headers: [String: String]) async throws

    /// Start playback.
    func play()

    /// Pause playback.
    func pause()

    /// Seek to a position in seconds.
    func seek(to seconds: TimeInterval) async

    /// Stop and clean up.
    func stop()

    /// Select an audio track by ID.
    func selectAudioTrack(id: String)

    /// Select a subtitle track by ID (nil to disable).
    func selectSubtitleTrack(id: String?)

    /// Set playback rate (1.0 = normal).
    func setRate(_ rate: Float)

    /// State change callback.
    var onStateChange: ((UnifiedPlaybackState) -> Void)? { get set }

    /// Time update callback (called periodically during playback).
    var onTimeUpdate: ((TimeInterval) -> Void)? { get set }

    /// Called when playback reaches end.
    var onPlaybackEnded: (() -> Void)? { get set }

    /// Called when an error occurs.
    var onError: ((String) -> Void)? { get set }

    /// The engine type.
    var engineType: PlaybackEngineType { get }
}

// MARK: - Engine Type

public enum PlaybackEngineType: String, Sendable, Equatable {
    case native = "AVPlayer"
    case vlc = "VLCKit"
}

// MARK: - Native Engine Video Access

/// Protocol for engines that provide an AVPlayer (native engine).
@MainActor
public protocol NativePlayerProviding: PlaybackEngineAdapter {
    var avPlayer: AVPlayer { get }
}
