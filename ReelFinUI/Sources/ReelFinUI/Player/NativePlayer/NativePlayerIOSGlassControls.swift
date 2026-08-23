#if os(iOS)
import SwiftUI

struct NativePlayerIOSGlassGroup<Content: View>: View {
    let spacing: CGFloat
    let height: CGFloat
    var horizontalPadding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            HStack(spacing: spacing) {
                content
            }
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .nativePlayerIOSGlassCapsule()
        }
    }
}

struct NativePlayerIOSIconButton: View {
    enum Size {
        case compact
        case large
        case transport
        case primaryTransport

        var frame: CGFloat {
            switch self {
            case .compact: 44
            case .large: 48
            case .transport: 62
            case .primaryTransport: 86
            }
        }

        var symbol: CGFloat {
            switch self {
            case .compact: 24
            case .large: 28
            case .transport: 34
            case .primaryTransport: 46
            }
        }

        var backgroundOpacity: Double {
            switch self {
            case .primaryTransport: 0.055
            default: 0.045
            }
        }
    }

    let systemName: String
    let size: Size
    var diameter: CGFloat? = nil
    var accessibilityLabel: String?
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size.symbol, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: diameter ?? size.frame, height: diameter ?? size.frame)
                .modifier(NativePlayerIOSIconChrome(size: size))
        }
        .buttonStyle(NativePlayerIOSButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel ?? systemName))
        .accessibilityIdentifier(accessibilityIdentifier ?? systemName)
    }
}

private struct NativePlayerIOSIconChrome: ViewModifier {
    let size: NativePlayerIOSIconButton.Size
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        switch size {
        case .compact:
            content
                .contentShape(Rectangle())
        case .large, .transport, .primaryTransport:
            if reduceTransparency {
                content
                    .contentShape(Circle())
                    .background(.black.opacity(0.72), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            } else {
                content
                    .contentShape(Circle())
                    .background {
                        Circle().fill(.white.opacity(size.backgroundOpacity))
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .overlay {
                        Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                    }
            }
        }
    }
}

struct NativePlayerIOSButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.96 : 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func nativePlayerIOSGlassCapsule() -> some View {
        modifier(NativePlayerIOSGlassCapsuleModifier())
    }
}

private struct NativePlayerIOSGlassCapsuleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.black.opacity(0.74), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1)
                }
        } else {
            content
                .background {
                    Capsule(style: .continuous).fill(.white.opacity(0.025))
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay {
                    Capsule(style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        }
    }
}
#endif
