enum TVLibraryActivationPolicy {
    static func activate(_ action: () -> Void) {
        action()
    }
}

#if os(tvOS)
import Shared
import SwiftUI

struct TVLibraryPosterCard: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let item: MediaItem
    let dependencies: ReelFinDependencies
    let isFocused: Bool
    var namespace: Namespace.ID? = nil
    var transitionSourceID: String? = nil
    let onFocus: (MediaItem) -> Void
    var onMoveUp: (() -> Void)? = nil
    let onSelect: (MediaItem) -> Void

    var body: some View {
        Button {
            TVLibraryActivationPolicy.activate {
                onSelect(item)
            }
        } label: {
            ZStack {
                restingSurface

                if focusedPresentation == .opaque {
                    surfaceShape.fill(ReelFinTheme.editorialOpaqueFallback)
                }

                VStack(alignment: .leading, spacing: ReelFinTheme.tvCardMetadataSpacing) {
                    PosterCardArtworkView(
                        item: item,
                        apiClient: dependencies.apiClient,
                        imagePipeline: dependencies.imagePipeline,
                        layoutStyle: .grid,
                        namespace: namespace,
                        transitionSourceID: transitionSourceID
                    )
                    .clipShape(surfaceShape)
                    .opacity(focusedPresentation == .opaque ? 0.82 : 1)

                    PosterCardMetadataView(
                        item: item,
                        layoutStyle: .grid,
                        titleLineLimit: 2
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 2)
                    .opacity(isFocused ? 1 : 0.74)
                }

                focusSurface
                    .allowsHitTesting(false)
            }
            .frame(width: cardContentWidth, alignment: .leading)
            .overlay {
                surfaceShape
                    .stroke(
                        ReelFinTheme.editorialFocusedRim,
                        lineWidth: TVFocusGeometry.focusedStrokeWidth
                    )
                    .opacity(isFocused ? 1 : 0)
            }
            .clipShape(surfaceShape)
            .contentShape(surfaceShape)
        }
        .buttonStyle(TVLibraryPosterPressStyle())
        .tvMotionFocus(.libraryPoster, isFocused: isFocused)
        .shadow(
            color: .black.opacity(isFocused ? TVFocusGeometry.focusedShadowOpacity : 0),
            radius: TVFocusGeometry.focusedShadowRadius,
            x: 0,
            y: TVFocusGeometry.focusedShadowY
        )
        .onMoveCommand(perform: handleMoveCommand)
        .focusEffectDisabled(true)
        .hoverEffectDisabled(true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("media_card_button_\(item.id)")
        .onChange(of: isFocused) { _, focused in
            guard focused else { return }
            onFocus(item)
        }
    }

    private var focusedPresentation: EditorialGlassPresentation? {
        guard isFocused else { return nil }
        return EditorialGlassRole.focusedMedia.presentation(
            reduceTransparency: reduceTransparency
        )
    }

    @ViewBuilder
    private var focusSurface: some View {
        if let focusedPresentation {
            switch focusedPresentation {
            case .passiveGlass:
                Color.clear
                    .glassEffect(
                        Glass.regular.tint(ReelFinTheme.editorialGlassTint),
                        in: .rect(cornerRadius: surfaceCornerRadius)
                    )
            case .opaque:
                Color.clear
            case .interactiveGlass:
                Color.clear
                    .glassEffect(
                        Glass.regular.tint(ReelFinTheme.editorialGlassTint).interactive(),
                        in: .rect(cornerRadius: surfaceCornerRadius)
                    )
            }
        } else {
            Color.clear
        }
    }

    private var restingSurface: some View {
        surfaceShape.fill(Color.white.opacity(0.04))
    }

    private var surfaceShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
    }

    private var cardContentWidth: CGFloat {
        240
    }

    private var surfaceCornerRadius: CGFloat {
        26
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard direction == .up else { return }
        onMoveUp?()
    }
}

private struct TVLibraryPosterPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                configuration.isPressed && !reduceMotion
                    ? TVFocusGeometry.libraryActivationScale
                    : 1
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                EditorialMotion.buttonPressAnimation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
#endif
