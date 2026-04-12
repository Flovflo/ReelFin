#if os(iOS)
import SwiftUI

struct iOS26StyleOnBoarding: View {
    var tint: Color = .blue
    var hideBezels: Bool = false
    var items: [Item]
    var onIndexChange: ((Int) -> Void)? = nil
    var onComplete: () -> ()
    /// View Properties
    @State private var currentIndex: Int
    @State private var screenshotSize: CGSize = .zero

    init(
        tint: Color = .blue,
        hideBezels: Bool = false,
        items: [Item],
        initialIndex: Int = 0,
        onIndexChange: ((Int) -> Void)? = nil,
        onComplete: @escaping () -> Void
    ) {
        self.tint = tint
        self.hideBezels = hideBezels
        self.items = items
        self.onIndexChange = onIndexChange
        self.onComplete = onComplete

        let lastIndex = max(items.count - 1, 0)
        let clampedInitialIndex = min(max(initialIndex, 0), lastIndex)
        _currentIndex = State(initialValue: clampedInitialIndex)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenshotView()
                .compositingGroup()
                .scaleEffect(
                    items[currentIndex].zoomScale,
                    anchor: items[currentIndex].zoomAnchor
                )
                .padding(.top, 35)
                .padding(.horizontal, 30)
                .padding(.bottom, 278)

            VStack(spacing: 10) {
                TextContentView()
                IndicatorView()
                ContinueButton()
            }
            .padding(.top, 20)
            .padding(.horizontal, 15)
            .frame(height: 268)
            .background {
                VariableGlassBlur(15)
            }

            BackButton()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            onIndexChange?(currentIndex)
        }
        .onChange(of: currentIndex) { _, newValue in
            onIndexChange?(newValue)
        }
    }

    /// Screenshot View
    @ViewBuilder
    func ScreenshotView() -> some View {
        let shape = ConcentricRectangle(corners: .concentric, isUniform: true)

        GeometryReader {
            let size = $0.size

            Rectangle()
                .fill(.black)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]

                        Group {
                            if let screenshot = item.screenshot {
                                Image(uiImage: screenshot)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .onGeometryChange(for: CGSize.self) {
                                        $0.size
                                    } action: { newValue in
                                        guard index == 0 && screenshotSize == .zero else { return }
                                        screenshotSize = newValue
                                    }
                                    .clipShape(shape)
                            } else {
                                Rectangle()
                                    .fill(.black)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollDisabled(true)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: .init(get: {
                return currentIndex
            }, set: { _ in }))
        }
        .clipShape(shape)
        .overlay {
            if screenshotSize != .zero && !hideBezels {
                ZStack(alignment: .top) {
                    /// Device Frame UI
                    ZStack {
                        shape
                            .stroke(.white, lineWidth: 6)

                        shape
                            .stroke(.black, lineWidth: 4)

                        shape
                            .stroke(.black, lineWidth: 6)
                            .padding(4)
                    }
                    .padding(-7)

                    DynamicIslandView()
                        .padding(.top, dynamicIslandTopInset)
                }
            }
        }
        .frame(
            maxWidth: screenshotSize.width == 0 ? nil : screenshotSize.width,
            maxHeight: screenshotSize.height == 0 ? nil : screenshotSize.height
        )
        .containerShape(RoundedRectangle(cornerRadius: deviceCornerRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Text Content View
    @ViewBuilder
    func TextContentView() -> some View {
        GeometryReader {
            let size = $0.size

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        let isActive = currentIndex == index

                        VStack(spacing: 6) {
                            Text(item.eyebrow)
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(.white.opacity(0.72))

                            Text(item.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .lineLimit(2)
                                .minimumScaleFactor(0.84)
                                .foregroundStyle(.white)
                                .accessibilityIdentifier(isActive ? "onboarding_title" : "onboarding_title_\(index)")

                            Text(item.subtitle)
                                .font(.callout)
                                .lineLimit(3)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.8))

                            if !item.highlights.isEmpty {
                                ViewThatFits {
                                    HStack(spacing: 8) {
                                        highlightChips(for: item)
                                    }

                                    VStack(spacing: 8) {
                                        highlightChips(for: item)
                                    }
                                }
                                .padding(.top, 4)
                            }

                            if let footnote = item.footnote {
                                Text(footnote)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(3)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.62))
                                    .padding(.top, 2)
                            }
                        }
                        .frame(width: size.width)
                        .compositingGroup()
                        /// Only The current Item is visible others are blurred out!
                        .blur(radius: isActive ? 0 : 30)
                        .opacity(isActive ? 1 : 0)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(true)
            .scrollTargetBehavior(.paging)
            .scrollClipDisabled()
            .scrollPosition(id: .init(get: {
                return currentIndex
            }, set: { _ in }))
        }
    }

    @ViewBuilder
    private func highlightChips(for item: Item) -> some View {
        ForEach(item.highlights, id: \.self) { highlight in
            Text(highlight)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.10), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    /// Indicator View
    @ViewBuilder
    func IndicatorView() -> some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let isActive: Bool = currentIndex == index

                Capsule()
                    .fill(.white.opacity(isActive ? 1 : 0.4))
                    .frame(width: isActive ? 25 : 6, height: 6)
            }
        }
        .padding(.bottom, 5)
        .accessibilityIdentifier("onboarding_progress")
    }

    /// Bottom Continue Button
    @ViewBuilder
    func ContinueButton() -> some View {
        Button {
            if currentIndex == items.count - 1 {
                onComplete()
            }

            withAnimation(animation) {
                currentIndex = min(currentIndex + 1, items.count - 1)
            }
        } label: {
            Text(
                items[currentIndex].buttonTitle ??
                    (currentIndex == items.count - 1 ? "Get Started" : "Continue")
            )
                .fontWeight(.medium)
                .contentTransition(.numericText())
                .padding(.vertical, 6)
        }
        .tint(tint)
        .buttonStyle(.glassProminent)
        .buttonSizing(.flexible)
        .padding(.horizontal, 30)
        .accessibilityIdentifier("onboarding_primary_cta")
    }

    /// Back Button
    @ViewBuilder
    func BackButton() -> some View {
        Button {
            withAnimation(animation) {
                currentIndex = max(currentIndex - 1, 0)
            }
        } label: {
            Image(systemName: "chevron.left")
                .font(.title3)
                .frame(width: 20, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 15)
        .padding(.top, 5)
        .opacity(currentIndex == 0 ? 0 : 1)
        .disabled(currentIndex == 0)
    }

    /// Variable Glass Effect Blur
    @ViewBuilder
    func VariableGlassBlur(_ radius: CGFloat) -> some View {
        /// ADJUST THESE PROPERTIES ACCORDING TO YOUR OWN NEEDS!
        let tint: Color = .black.opacity(0.5)
        Rectangle()
            .fill(tint)
            .glassEffect(.clear, in: .rect)
            .blur(radius: radius)
            .padding([.horizontal, .bottom], -radius * 2)
            .padding(.top, -radius / 2)
            /// Only Visible for scaled screenshots!
            .opacity(items[currentIndex].zoomScale > 1 ? 1 : 0)
            .ignoresSafeArea()
    }

    @ViewBuilder
    func DynamicIslandView() -> some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.98))
            .frame(width: dynamicIslandWidth, height: dynamicIslandHeight)
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
            .allowsHitTesting(false)
    }

    var deviceCornerRadius: CGFloat {
        if let imageSize = items.first?.screenshot?.size {
            let ratio = screenshotSize.height / imageSize.height
            let actualCornerRadius: CGFloat = 180
            return actualCornerRadius * ratio
        }

        return 0
    }

    var dynamicIslandWidth: CGFloat {
        min(max(screenshotSize.width * 0.34, 88), 126)
    }

    var dynamicIslandHeight: CGFloat {
        min(max(screenshotSize.width * 0.09, 24), 34)
    }

    var dynamicIslandTopInset: CGFloat {
        min(max(screenshotSize.height * 0.027, 10), 18)
    }

    struct Item: Identifiable, Hashable {
        var id: Int
        var eyebrow: String
        var title: String
        var subtitle: String
        var screenshot: UIImage?
        var highlights: [String] = []
        var footnote: String? = nil
        var buttonTitle: String? = nil
        var zoomScale: CGFloat = 1
        var zoomAnchor: UnitPoint = .center
    }

    /// Customize it according to your needs!
    var animation: Animation {
        .interpolatingSpring(duration: 0.65, bounce: 0, initialVelocity: 0)
    }
}
#endif
