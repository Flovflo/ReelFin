#if os(iOS)
import SwiftUI

struct NativePlayerIOSGlassGroup<Content: View>: View {
    let spacing: CGFloat
    let height: CGFloat
    var horizontalPadding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
        .nativePlayerIOSGlassCapsule()
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
            case .compact: 28
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size.symbol, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size.frame, height: size.frame)
                .modifier(NativePlayerIOSIconChrome(size: size))
        }
        .buttonStyle(NativePlayerIOSButtonStyle())
    }
}

private struct NativePlayerIOSIconChrome: ViewModifier {
    let size: NativePlayerIOSIconButton.Size

    @ViewBuilder
    func body(content: Content) -> some View {
        switch size {
        case .compact:
            content
                .contentShape(Rectangle())
        case .large, .transport, .primaryTransport:
            content
                .contentShape(Circle())
                .background {
                    Circle()
                        .fill(.white.opacity(size.backgroundOpacity))
                        .glassEffect(.clear.interactive(), in: .circle)
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
        }
    }
}

struct NativePlayerIOSButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func nativePlayerIOSGlassCapsule() -> some View {
        background {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.028))
                .glassEffect(.clear.interactive(), in: .capsule)
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
    }
}
#endif
