import PlaybackEngine
import Shared
import SwiftUI

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
    var session: PlaybackSessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // ── Audio ────────────────────────────────────────────────
                if !session.availableAudioTracks.isEmpty {
                    Section {
                        ForEach(session.availableAudioTracks) { track in
                            TrackRow(
                                title: displayLanguage(for: track),
                                badge: audioBadge(for: track),
                                isSelected: session.selectedAudioTrackID == track.id
                            ) {
                                session.selectAudioTrack(id: track.id)
                            }
                        }
                    } header: {
                        Label("Piste audio", systemImage: "speaker.wave.2")
                    }
                }

                // ── Subtitles ────────────────────────────────────────────
                if !session.availableSubtitleTracks.isEmpty {
                    Section {
                        // "None" option
                        TrackRow(
                            title: "Aucun",
                            badge: nil,
                            icon: "minus.circle",
                            isSelected: session.selectedSubtitleTrackID == nil
                        ) {
                            session.selectSubtitleTrack(id: nil)
                        }

                        ForEach(session.availableSubtitleTracks) { track in
                            TrackRow(
                                title: displayLanguage(for: track),
                                badge: subtitleBadge(for: track),
                                isSelected: session.selectedSubtitleTrackID == track.id
                            ) {
                                session.selectSubtitleTrack(id: track.id)
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

    // MARK: - Helpers

    /// Human-readable language name derived from the track's BCP-47 language tag.
    /// Falls back to the raw title when no localized name is available.
    private func displayLanguage(for track: MediaTrack) -> String {
        if let lang = track.language, !lang.isEmpty {
            // Normalize ISO 639-2 ("fra", "eng") → 639-1 ("fr", "en") before lookup.
            let base = String(lang.prefix(2)).lowercased()
            if let localized = Locale.current.localizedString(forLanguageCode: base) {
                return localized
            }
        }
        return track.title.isEmpty ? "Piste \(track.index)" : track.title
    }

    private func audioBadge(for track: MediaTrack) -> String? {
        var parts: [String] = []
        if let codec = track.codec {
            parts.append(normalizedAudioCodecLabel(codec))
        }
        if track.isDefault { parts.append("Défaut") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func subtitleBadge(for track: MediaTrack) -> String? {
        var parts: [String] = []
        if let codec = track.codec, !codec.isEmpty {
            parts.append(codec.uppercased())
        }
        let lower = track.title.lowercased()
        if track.isForced || lower.contains("forced") || lower.contains("forcé") { parts.append("Forcé") }
        if track.isDefault { parts.append("Défaut") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Pretty-print common audio codec identifiers.
    private func normalizedAudioCodecLabel(_ codec: String) -> String {
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
