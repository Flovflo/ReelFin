import PlaybackEngine
import SwiftUI

public enum ApplePlaybackOptimizationStatus: Equatable, Sendable {
    case optimized
    case needsServerPrep

    init?(selection: PlaybackAssetSelection?) {
        guard let selection else { return nil }
        self = selection.isAppleOptimized ? .optimized : .needsServerPrep
    }

    var symbolName: String {
        switch self {
        case .optimized:
            return "bolt.fill"
        case .needsServerPrep:
            return "bolt.slash.fill"
        }
    }

    var detailLabel: String {
        switch self {
        case .optimized:
            return "Direct Play"
        case .needsServerPrep:
            return "Server Prep"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .optimized:
            return "Ready for direct play on Apple devices"
        case .needsServerPrep:
            return "Server preparation recommended before Apple playback"
        }
    }

    var iconTint: Color {
        switch self {
        case .optimized:
            return Color(red: 1.0, green: 0.86, blue: 0.24)
        case .needsServerPrep:
            return Color.white.opacity(0.60)
        }
    }

    var capsuleTint: Color {
        switch self {
        case .optimized:
            return Color(red: 1.0, green: 0.82, blue: 0.16).opacity(0.20)
        case .needsServerPrep:
            return Color.white.opacity(0.06)
        }
    }
}

struct ApplePlaybackPosterBadge: View {
    let status: ApplePlaybackOptimizationStatus

    var body: some View {
        Image(systemName: status.symbolName)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(status.iconTint)
            .frame(width: 28, height: 28)
            .reelFinGlassCircle(
                tint: status.capsuleTint,
                stroke: status.iconTint.opacity(0.28),
                shadowOpacity: 0.12,
                shadowRadius: 10,
                shadowYOffset: 4
            )
            .accessibilityLabel(status.accessibilityLabel)
    }
}

struct ApplePlaybackDetailBadge: View {
    let status: ApplePlaybackOptimizationStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.symbolName)
                .font(.system(size: 12, weight: .bold))

            Text(status.detailLabel)
                .lineLimit(1)
        }
        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
        .foregroundStyle(status.iconTint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .reelFinGlassCapsule(
            tint: status.capsuleTint,
            stroke: status.iconTint.opacity(0.22),
            shadowOpacity: 0.10,
            shadowRadius: 12,
            shadowYOffset: 6
        )
        .accessibilityLabel(status.accessibilityLabel)
    }

    private var fontSize: CGFloat {
#if os(tvOS)
        return 15
#else
        return 12
#endif
    }
}
