import Shared
import SwiftUI
import PlaybackEngine

enum PlaybackControlSelection {
    case audio(String)
    case subtitle(String?)
}

struct PlaybackTrackOption: Identifiable, Equatable {
    let trackID: String?
    let title: String
    let badge: String?
    let iconName: String?
    let isSelected: Bool

    var id: String {
        trackID ?? "__none__"
    }
}

struct PlaybackControlsModel: Equatable {
    var skipSuggestion: PlaybackSkipSuggestion?
    var audioOptions: [PlaybackTrackOption]
    var subtitleOptions: [PlaybackTrackOption]

    init(
        skipSuggestion: PlaybackSkipSuggestion? = nil,
        audioOptions: [PlaybackTrackOption] = [],
        subtitleOptions: [PlaybackTrackOption] = []
    ) {
        self.skipSuggestion = skipSuggestion
        self.audioOptions = audioOptions
        self.subtitleOptions = subtitleOptions
    }

    var hasSelectableTracks: Bool {
        !audioOptions.isEmpty || !subtitleOptions.isEmpty
    }

    static func make(
        audioTracks: [MediaTrack],
        subtitleTracks: [MediaTrack],
        selectedAudioID: String?,
        selectedSubtitleID: String?,
        skipSuggestion: PlaybackSkipSuggestion?
    ) -> PlaybackControlsModel {
        let audioOptions: [PlaybackTrackOption]
        if audioTracks.count > 1 {
            audioOptions = audioTracks.map { track in
                PlaybackTrackOption(
                    trackID: track.id,
                    title: PlaybackTrackPresentation.title(for: track),
                    badge: PlaybackTrackPresentation.audioBadge(for: track),
                    iconName: nil,
                    isSelected: track.id == selectedAudioID
                )
            }
        } else {
            audioOptions = []
        }

        let subtitleOptions: [PlaybackTrackOption]
        if subtitleTracks.isEmpty {
            subtitleOptions = []
        } else {
            subtitleOptions = [
                PlaybackTrackOption(
                    trackID: nil,
                    title: "Aucun",
                    badge: nil,
                    iconName: "minus.circle",
                    isSelected: selectedSubtitleID == nil
                )
            ] + subtitleTracks.map { track in
                PlaybackTrackOption(
                    trackID: track.id,
                    title: PlaybackTrackPresentation.title(for: track),
                    badge: PlaybackTrackPresentation.subtitleBadge(for: track),
                    iconName: nil,
                    isSelected: track.id == selectedSubtitleID
                )
            }
        }

        return PlaybackControlsModel(
            skipSuggestion: skipSuggestion,
            audioOptions: audioOptions,
            subtitleOptions: subtitleOptions
        )
    }
}

enum PlaybackTrackPresentation {
    static func title(for track: MediaTrack) -> String {
        if let lang = track.language, !lang.isEmpty {
            let base = String(lang.prefix(2)).lowercased()
            if let localized = Locale.current.localizedString(forLanguageCode: base) {
                return localized.capitalized
            }
        }
        return track.title.isEmpty ? "Piste \(track.index)" : track.title
    }

    static func audioBadge(for track: MediaTrack) -> String? {
        var parts: [String] = []
        if let codec = track.codec {
            parts.append(normalizedAudioCodecLabel(codec))
        }
        if track.isDefault {
            parts.append("Défaut")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func subtitleBadge(for track: MediaTrack) -> String? {
        var parts: [String] = []
        if let codec = track.codec, !codec.isEmpty {
            parts.append(codec.uppercased())
        }
        let lower = track.title.lowercased()
        if track.isForced || lower.contains("forced") || lower.contains("forcé") {
            parts.append("Forcé")
        }
        if track.isDefault {
            parts.append("Défaut")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func normalizedAudioCodecLabel(_ codec: String) -> String {
        switch codec.lowercased() {
        case "eac3", "ec-3", "ec3":
            return "Dolby Digital+"
        case "ac3":
            return "Dolby Digital"
        case "truehd":
            return "TrueHD"
        case "dts":
            return "DTS"
        case "dts-hd", "dtshd", "dtshd-ma", "dtshd_ma":
            return "DTS-HD MA"
        case "aac":
            return "AAC"
        case "flac":
            return "FLAC"
        case "mp3":
            return "MP3"
        case "opus":
            return "Opus"
        default:
            return codec.uppercased()
        }
    }
}

/// A sheet that lets the user switch audio language and subtitle tracks
/// for the current playback session.
///
/// Audio switching is backed by `PlaybackSessionController.selectAudioTrack(id:)`,
/// which first tries a native AVMediaSelectionGroup switch (embedded multi-track
/// containers) and falls back to a seamless DirectPlay reload with the desired
/// `AudioStreamIndex`.
///
/// Subtitle switching uses `selectSubtitleTrack(id:)`, which similarly tries
/// the native legible group before falling back to an HLS reload with
/// `SubtitleStreamIndex=N&SubtitleMethod=Hls` so Jellyfin can embed the
/// sidecar subtitle track in the manifest.
struct TrackPickerView: View {
    let controls: PlaybackControlsModel
    let onSelect: (PlaybackControlSelection) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // ── Audio ────────────────────────────────────────────────
                if !controls.audioOptions.isEmpty {
                    Section {
                        ForEach(controls.audioOptions) { option in
                            TrackRow(
                                title: option.title,
                                badge: option.badge,
                                isSelected: option.isSelected
                            ) {
                                guard let trackID = option.trackID else { return }
                                onSelect(.audio(trackID))
                            }
                        }
                    } header: {
                        Label("Piste audio", systemImage: "speaker.wave.2")
                    }
                }

                // ── Subtitles ────────────────────────────────────────────
                if !controls.subtitleOptions.isEmpty {
                    Section {
                        ForEach(controls.subtitleOptions) { option in
                            TrackRow(
                                title: option.title,
                                badge: option.badge,
                                icon: option.iconName,
                                isSelected: option.isSelected
                            ) {
                                onSelect(.subtitle(option.trackID))
                            }
                        }
                    } header: {
                        Label("Sous-titres", systemImage: "captions.bubble")
                    }
                }
            }
            .navigationTitle("Pistes")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }

}

// MARK: - Track Row

private struct TrackRow: View {
    let title: String
    let badge: String?
    var icon: String? = nil
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)

                    if let badge {
                        Text(badge)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}
