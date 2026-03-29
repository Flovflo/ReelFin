#if os(tvOS)
import SwiftUI

struct TVLibraryPillButton: View {
    @FocusState private var isFocused: Bool

    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if #available(tvOS 26.0, *) {
                modernButton
            } else {
                legacyButton
            }
        }
    }

    private var baseButton: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                }

                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .font(.system(size: 21, weight: .semibold, design: .rounded))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(minHeight: 60)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .focusEffectDisabled(true)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @available(tvOS 26.0, *)
    @ViewBuilder
    private var modernButton: some View {
        if isFocused || isSelected {
            baseButton
                .glassEffect(Glass.regular.interactive(), in: .capsule)
        } else {
            baseButton
                .foregroundStyle(Color.white.opacity(0.92))
                .glassEffect(
                    Glass.regular.tint(Color.white.opacity(0.04)),
                    in: .capsule
                )
        }
    }

    @ViewBuilder
    private var legacyButton: some View {
        if isFocused || isSelected {
            baseButton
                .foregroundStyle(Color.black.opacity(0.92))
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.92))
                }
        } else {
            baseButton
                .foregroundStyle(Color.white.opacity(0.92))
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                }
        }
    }
}
#endif
