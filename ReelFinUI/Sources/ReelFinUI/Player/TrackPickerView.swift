import Shared
import SwiftUI
import PlaybackEngine

enum PlaybackControlSelection {
    case audio(String)
    case subtitle(String?)
}

enum PlaybackTrackMenuKind: Equatable {
    case audio
    case subtitles
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

    func options(for menu: PlaybackTrackMenuKind) -> [PlaybackTrackOption] {
        switch menu {
        case .audio:
            return audioOptions
        case .subtitles:
            return subtitleOptions
        }
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
                    title: "Off",
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

struct NativePlayerTrackSelectionMenuView: View {
    let mode: PlaybackTrackMenuKind
    let controls: PlaybackControlsModel
    let onSelect: (PlaybackControlSelection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            Text(primaryTitle)
                .font(.system(size: metrics.titleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .padding(.horizontal, metrics.horizontalPadding)

            ScrollView {
                if mode == .audio {
                    audioTrackSection
                } else {
                    subtitlesSection
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: metrics.contentMaxHeight)
        }
        .padding(.vertical, metrics.verticalPadding)
        .frame(width: metrics.panelWidth, alignment: .leading)
        .nativePlayerTrackMenuGlass(cornerRadius: metrics.cornerRadius)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var audioTrackSection: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            if controls.audioOptions.isEmpty {
                NativePlayerTrackMenuEmptyRow(title: "No alternate audio")
            } else {
                sectionLabel("Audio Track")
                ForEach(controls.audioOptions) { option in
                    NativePlayerTrackMenuRow(option: option) {
                        guard let trackID = option.trackID else { return }
                        onSelect(.audio(trackID))
                    }
                }
            }
        }
    }

    private var subtitlesSection: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            if controls.subtitleOptions.isEmpty {
                NativePlayerTrackMenuEmptyRow(title: "No subtitles")
            } else {
                ForEach(controls.subtitleOptions) { option in
                    NativePlayerTrackMenuRow(option: option) {
                        onSelect(.subtitle(option.trackID))
                    }
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: metrics.sectionTitleSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.46))
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, mode == .audio ? 4 : 0)
    }

    private var primaryTitle: String {
        switch mode {
        case .audio:
            return "Audio Adjustments"
        case .subtitles:
            return "Subtitles"
        }
    }

    private var accessibilityIdentifier: String {
        switch mode {
        case .audio:
            return "native_player_audio_menu"
        case .subtitles:
            return "native_player_subtitles_menu"
        }
    }

    private var metrics: NativePlayerTrackMenuMetrics {
        NativePlayerTrackMenuMetrics.current
    }
}

private struct NativePlayerTrackMenuRow: View {
    let option: PlaybackTrackOption
    let onSelect: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 18) {
                Image(systemName: "checkmark")
                    .font(.system(size: metrics.checkSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(option.isSelected ? foreground : .clear)
                    .frame(width: metrics.checkColumnWidth)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: metrics.rowTitleSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if let badge = option.badge {
                        Text(badge)
                            .font(.system(size: metrics.badgeSize, weight: .medium, design: .rounded))
                            .foregroundStyle(foreground.opacity(isHighlighted ? 0.62 : 0.46))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.rowHorizontalPadding)
            .frame(height: metrics.rowHeight)
            .contentShape(Capsule(style: .continuous))
            .background {
                Capsule(style: .continuous)
                    .fill(isHighlighted ? Color.white.opacity(0.96) : Color.clear)
            }
        }
        .buttonStyle(TVNoChromeButtonStyle())
        .focused($isFocused)
        .nativePlayerTrackMenuFocusDisabled()
        .padding(.horizontal, metrics.rowOuterPadding)
        .accessibilityLabel(option.title)
    }

    private var isHighlighted: Bool {
        isFocused || option.isSelected
    }

    private var foreground: Color {
        isHighlighted ? .black : .white
    }

    private var metrics: NativePlayerTrackMenuMetrics {
        NativePlayerTrackMenuMetrics.current
    }
}

private struct NativePlayerTrackMenuEmptyRow: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: NativePlayerTrackMenuMetrics.current.rowTitleSize, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, NativePlayerTrackMenuMetrics.current.horizontalPadding)
            .frame(height: NativePlayerTrackMenuMetrics.current.rowHeight)
            .accessibilityLabel(title)
    }
}

private struct NativePlayerTrackMenuMetrics {
    let panelWidth: CGFloat
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let sectionSpacing: CGFloat
    let rowSpacing: CGFloat
    let rowHeight: CGFloat
    let rowOuterPadding: CGFloat
    let rowHorizontalPadding: CGFloat
    let checkColumnWidth: CGFloat
    let titleSize: CGFloat
    let sectionTitleSize: CGFloat
    let rowTitleSize: CGFloat
    let badgeSize: CGFloat
    let checkSize: CGFloat
    let contentMaxHeight: CGFloat

    static var current: NativePlayerTrackMenuMetrics {
#if os(tvOS)
        NativePlayerTrackMenuMetrics(
            panelWidth: 690,
            cornerRadius: 58,
            horizontalPadding: 58,
            verticalPadding: 42,
            sectionSpacing: 36,
            rowSpacing: 14,
            rowHeight: 88,
            rowOuterPadding: 28,
            rowHorizontalPadding: 34,
            checkColumnWidth: 48,
            titleSize: 38,
            sectionTitleSize: 34,
            rowTitleSize: 38,
            badgeSize: 21,
            checkSize: 34,
            contentMaxHeight: 560
        )
#else
        NativePlayerTrackMenuMetrics(
            panelWidth: 320,
            cornerRadius: 30,
            horizontalPadding: 24,
            verticalPadding: 20,
            sectionSpacing: 16,
            rowSpacing: 6,
            rowHeight: 50,
            rowOuterPadding: 10,
            rowHorizontalPadding: 18,
            checkColumnWidth: 28,
            titleSize: 21,
            sectionTitleSize: 18,
            rowTitleSize: 21,
            badgeSize: 12,
            checkSize: 18,
            contentMaxHeight: 250
        )
#endif
    }
}

private extension View {
    func nativePlayerTrackMenuGlass(cornerRadius: CGFloat) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.72))
                .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1.2)
        }
        .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
    }

    @ViewBuilder
    func nativePlayerTrackMenuFocusDisabled() -> some View {
#if os(tvOS)
        self
            .focusEffectDisabled(true)
            .hoverEffectDisabled(true)
#else
        self
#endif
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
                                select(.audio(trackID))
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
                                select(.subtitle(option.trackID))
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
        .accessibilityIdentifier("player_track_picker_sheet")
    }

    private func select(_ selection: PlaybackControlSelection) {
        onSelect(selection)
        dismiss()
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
