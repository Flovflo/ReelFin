import SwiftUI

#if os(iOS)
import VariableBlur

private struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum StickyBlurHeaderVisibility {
    case always
    case revealOnScroll(distance: CGFloat, minimumEffectOpacity: CGFloat)
}

/// Local fork kept intentionally close to dominikmartn/ProgressiveBlurHeader,
/// with small ReelFin-specific extensions for `refreshable` and Home reveal tuning.
struct StickyBlurHeader<Header: View, Content: View>: View {
    private let maxBlurRadius: CGFloat
    private let fadeExtension: CGFloat
    private let tintOpacityTop: Double
    private let tintOpacityMiddle: Double
    private let statusBarBlurOpacity: Double
    private let contentTopInset: CGFloat?
    private let visibility: StickyBlurHeaderVisibility
    private let refreshAction: (() async -> Void)?
    private let header: (CGFloat) -> Header
    private let content: () -> Content

    @State private var headerHeight: CGFloat = 76
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    init(
        maxBlurRadius: CGFloat = 5,
        fadeExtension: CGFloat = 64,
        tintOpacityTop: Double = 0.7,
        tintOpacityMiddle: Double = 0.5,
        statusBarBlurOpacity: Double = 0,
        contentTopInset: CGFloat? = nil,
        visibility: StickyBlurHeaderVisibility = .always,
        refreshAction: (() async -> Void)? = nil,
        @ViewBuilder header: @escaping (CGFloat) -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.maxBlurRadius = maxBlurRadius
        self.fadeExtension = fadeExtension
        self.tintOpacityTop = tintOpacityTop
        self.tintOpacityMiddle = tintOpacityMiddle
        self.statusBarBlurOpacity = statusBarBlurOpacity
        self.contentTopInset = contentTopInset
        self.visibility = visibility
        self.refreshAction = refreshAction
        self.header = header
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            scrollLayer

            let totalHeight = headerHeight + fadeExtension
            let blurMask = LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.94), location: 0.08),
                    .init(color: .black.opacity(0.68), location: 0.22),
                    .init(color: .black.opacity(0.28), location: 0.42),
                    .init(color: .black.opacity(0.10), location: 0.62),
                    .init(color: .clear, location: 0.86),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if statusBarBlurOpacity > 0 {
                let topBandMask = LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.96), location: 0.24),
                        .init(color: .black.opacity(0.42), location: 0.74),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                TransparentBlurView(style: .systemMaterialDark)
                    .mask { topBandMask }
                    .frame(height: headerHeight + 30)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                    .opacity(headerEffectOpacity * statusBarBlurOpacity)

                VariableBlurView(
                    maxBlurRadius: maxBlurRadius * 1.35,
                    direction: .blurredTopClearBottom
                )
                .mask { topBandMask }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: fadeTint.opacity(statusBarBlurOpacity * 0.52), location: 0),
                            .init(color: fadeTint.opacity(statusBarBlurOpacity * 0.28), location: 0.40),
                            .init(color: fadeTint.opacity(0), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: headerHeight + 46)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .opacity(headerEffectOpacity * statusBarBlurOpacity)
            }

            TransparentBlurView(style: .systemUltraThinMaterialDark)
                .mask { blurMask }
                .frame(height: totalHeight)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .opacity(headerEffectOpacity * 0.05)

            VariableBlurView(
                maxBlurRadius: maxBlurRadius,
                direction: .blurredTopClearBottom
            )
            .mask { blurMask }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: fadeTint.opacity(tintOpacityTop), location: 0),
                            .init(color: fadeTint.opacity(tintOpacityTop * 0.92), location: 0.08),
                            .init(
                                color: fadeTint.opacity((tintOpacityTop + tintOpacityMiddle) * 0.58),
                                location: 0.24
                            ),
                            .init(color: fadeTint.opacity(tintOpacityMiddle), location: 0.42),
                            .init(color: fadeTint.opacity(tintOpacityMiddle * 0.42), location: 0.60),
                            .init(color: fadeTint.opacity(0), location: 0.82),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
            }
            .frame(height: totalHeight)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .opacity(headerEffectOpacity)

            header(headerRevealProgress)
                .overlay {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: HeaderHeightKey.self,
                            value: geo.size.height
                        )
                    }
                }
        }
        .onPreferenceChange(HeaderHeightKey.self) { headerHeight = $0 }
    }

    @ViewBuilder
    private var scrollLayer: some View {
        let baseScrollView = ScrollView {
            content()
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: contentTopInset ?? headerHeight)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, newValue in
            scrollOffset = newValue
        }

        if let refreshAction {
            if contentTopInset == 0 {
                baseScrollView
                    .refreshable {
                        await refreshAction()
                    }
                    .ignoresSafeArea(edges: .top)
            } else {
                baseScrollView.refreshable {
                    await refreshAction()
                }
            }
        } else {
            if contentTopInset == 0 {
                baseScrollView
                    .ignoresSafeArea(edges: .top)
            } else {
                baseScrollView
            }
        }
    }

    private var fadeTint: Color {
        colorScheme == .dark ? .black : .white
    }

    private var headerRevealProgress: CGFloat {
        switch visibility {
        case .always:
            return 1
        case let .revealOnScroll(distance, _):
            guard distance > 0 else { return 1 }
            return min(max(scrollOffset / distance, 0), 1)
        }
    }

    private var headerEffectOpacity: CGFloat {
        switch visibility {
        case .always:
            return 1
        case let .revealOnScroll(_, minimumEffectOpacity):
            return minimumEffectOpacity + ((1 - minimumEffectOpacity) * headerRevealProgress)
        }
    }
}
#endif
