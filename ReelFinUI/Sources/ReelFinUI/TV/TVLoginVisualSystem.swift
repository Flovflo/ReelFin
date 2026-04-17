#if os(tvOS)
import SwiftUI

struct TVLoginBrandHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("ReelFin")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text("for Jellyfin")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.76))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Color.clear.reelFinGlassRoundedRect(
                        cornerRadius: 18,
                        tint: Color.white.opacity(0.05),
                        stroke: Color.white.opacity(0.07),
                        shadowOpacity: 0.06,
                        shadowRadius: 8,
                        shadowYOffset: 4
                    )
                }
        }
    }
}

struct TVLoginStageSurface<Content: View>: View {
    let metrics: TVLoginLayoutMetrics
    let content: Content

    init(
        metrics: TVLoginLayoutMetrics,
        @ViewBuilder content: () -> Content
    ) {
        self.metrics = metrics
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, metrics.panelHorizontalPadding)
            .padding(.vertical, metrics.panelVerticalPadding)
            .frame(width: metrics.panelWidth)
            .background {
                ZStack {
                    Color.clear.reelFinGlassRoundedRect(
                        cornerRadius: 38,
                        tint: Color.white.opacity(0.045),
                        stroke: Color.white.opacity(0.08),
                        shadowOpacity: 0.14,
                        shadowRadius: 24,
                        shadowYOffset: 12
                    )

                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.14),
                                    Color.black.opacity(0.06)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
    }
}

struct TVLoginStageHeading: View {
    let title: String
    let subtitle: String
    let titleSize: CGFloat

    init(title: String, subtitle: String, titleSize: CGFloat = 48) {
        self.title = title
        self.subtitle = subtitle
        self.titleSize = titleSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TVLoginChip: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)

            Text(text)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
            .background {
                Color.clear.reelFinGlassRoundedRect(
                    cornerRadius: 22,
                    tint: Color.white.opacity(0.06),
                    stroke: Color.white.opacity(0.08),
                    shadowOpacity: 0.08,
                    shadowRadius: 12,
                    shadowYOffset: 6
                )
            }
    }
}

struct TVLoginActionButton: View {
    enum Style {
        case primary
        case secondary
        case tertiary
    }

    let title: String
    let icon: String
    let style: Style
    let isLoading: Bool
    let isEnabled: Bool
    let accessibilityIdentifier: String?
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    init(
        title: String,
        icon: String,
        style: Style = .primary,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        if #available(tvOS 26.0, *) {
            styledGlassButton
        } else {
            switch style {
            case .primary:
                button
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            case .secondary:
                button
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.16))
                    .foregroundStyle(.white)
            case .tertiary:
                button
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.08))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
    }

    @available(tvOS 26.0, *)
    @ViewBuilder
    private var styledGlassButton: some View {
        if isFocused {
            button
                .buttonStyle(.glassProminent)
                .opacity(baseOpacity)
        } else {
            button
                .buttonStyle(.glass)
                .opacity(baseOpacity)
        }
    }

    private var baseOpacity: CGFloat {
        if isFocused {
            return 1
        }

        switch style {
        case .primary:
            return 1
        case .secondary:
            return 0.97
        case .tertiary:
            return 0.90
        }
    }

    private var button: some View {
        Button(action: action) {
            TVLoginActionLabel(
                title: title,
                icon: icon,
                style: style,
                isLoading: isLoading
            )
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .opacity(isEnabled ? 1 : 0.65)
        }
        .buttonBorderShape(.roundedRectangle(radius: 28))
        .controlSize(.large)
        .disabled(!isEnabled || isLoading)
        .scaleEffect(isFocused ? 1.02 : 1)
        .animation(ReelFinTheme.tvFocusSpring, value: isFocused)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

private struct TVLoginActionLabel: View {
    let title: String
    let icon: String
    let style: TVLoginActionButton.Style
    let isLoading: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(foregroundColor)
                }
            }
            .frame(width: 26)

            Text(title)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .foregroundStyle(foregroundColor)
        }
    }

    private var foregroundColor: Color {
        if isFocused {
            return Color.black.opacity(0.84)
        }

        switch style {
        case .primary:
            return .white.opacity(0.96)
        case .secondary:
            return .white.opacity(0.92)
        case .tertiary:
            return .white.opacity(0.82)
        }
    }
}

extension View {
    func tvLoginFieldSurface(focused: Bool) -> some View {
        self
            .textFieldStyle(.plain)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(Color.clear)
            .shadow(color: .black.opacity(focused ? 0.14 : 0.08), radius: focused ? 10 : 6, x: 0, y: focused ? 6 : 3)
    }
}
#endif
