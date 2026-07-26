import CoreGraphics

struct IOSDetailScrollPresentation: Equatable {
    static let expanded = IOSDetailScrollPresentation(
        heroStep: 0,
        chromeStep: 0,
        allowsHorizontalSelection: true
    )

    let heroStep: Int
    let chromeStep: Int
    let allowsHorizontalSelection: Bool

    var heroProgress: CGFloat {
        CGFloat(heroStep) / CGFloat(IOSDetailCarouselLayout.heroStepCount)
    }

    var chromeProgress: CGFloat {
        CGFloat(chromeStep) / CGFloat(IOSDetailCarouselLayout.chromeStepCount)
    }
}

enum IOSDetailCarouselLayout {
    static let verticalScrollLockThreshold: CGFloat = 0.01
    static let heroStepCount = 32
    static let chromeStepCount = 12
    static let selectedShadowRadius: CGFloat = 30
    static let selectedShadowYOffset: CGFloat = 24
    static let previewShadowRadius: CGFloat = 18
    static let previewShadowYOffset: CGFloat = 12

    private static let scrollTopSlop: CGFloat = 10
    private static let reduceMotionCollapseThreshold: CGFloat = 0.5

    static func presentation(
        offsetY: CGFloat,
        topInset: CGFloat,
        heroHeight: CGFloat,
        topTriggerDistance: CGFloat,
        reduceMotion: Bool
    ) -> IOSDetailScrollPresentation {
        let effectiveOffset = max(0, offsetY + topInset - scrollTopSlop)
        let rawHeroProgress = clampedProgress(
            effectiveOffset / max(heroHeight * 0.54, 1)
        )
        let rawChromeProgress = clampedProgress(
            effectiveOffset / max(topTriggerDistance, 1)
        )
        let allowsSelection = allowsHorizontalSelection(
            topInsetProgress: rawChromeProgress
        )

        if reduceMotion {
            let isCollapsed = rawChromeProgress > reduceMotionCollapseThreshold
            return IOSDetailScrollPresentation(
                heroStep: isCollapsed ? heroStepCount : 0,
                chromeStep: isCollapsed ? chromeStepCount : 0,
                allowsHorizontalSelection: allowsSelection
            )
        }

        return IOSDetailScrollPresentation(
            heroStep: quantizedStep(rawHeroProgress, count: heroStepCount),
            chromeStep: quantizedStep(rawChromeProgress, count: chromeStepCount),
            allowsHorizontalSelection: allowsSelection
        )
    }

    static func cardWidth(
        for availableWidth: CGFloat,
        minimumPadding: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let maxWidth = max(availableWidth - (minimumPadding * 2), 0)

        if usesCompactLayout(for: viewportWidth) {
            return maxWidth
        }

        return min(maxWidth, 760)
    }

    static func sideInset(
        for availableWidth: CGFloat,
        cardWidth: CGFloat,
        minimumPadding: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let centeredInset = max((availableWidth - cardWidth) * 0.5, 0)

        if usesCompactLayout(for: viewportWidth) {
            return minimumPadding
        }

        return max(centeredInset, minimumPadding)
    }

    static func allowsHorizontalSelection(topInsetProgress: CGFloat) -> Bool {
        topInsetProgress <= verticalScrollLockThreshold
    }

    static func neighborPreviewOpacity(topInsetProgress: CGFloat) -> Double {
        let normalizedProgress = min(max(topInsetProgress / verticalScrollLockThreshold, 0), 1)
        return Double(1 - normalizedProgress)
    }

    static func acceptedSelectionID(
        currentItemID: String,
        proposedItemID: String?,
        topInsetProgress: CGFloat
    ) -> String? {
        guard allowsHorizontalSelection(topInsetProgress: topInsetProgress) else { return nil }
        guard let proposedItemID, proposedItemID != currentItemID else { return nil }
        return proposedItemID
    }

    private static func usesCompactLayout(for viewportWidth: CGFloat) -> Bool {
        viewportWidth < 430
    }

    private static func clampedProgress(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private static func quantizedStep(_ progress: CGFloat, count: Int) -> Int {
        min(max(Int((progress * CGFloat(count)).rounded()), 0), count)
    }
}
