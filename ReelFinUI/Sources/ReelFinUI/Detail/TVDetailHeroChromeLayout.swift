import CoreGraphics

struct TVDetailHeroChromePresentation: Equatable {
    static let resting = TVDetailHeroChromePresentation(
        collapseStep: 0,
        previewInteractionEnabled: true
    )

    let collapseStep: Int
    let previewInteractionEnabled: Bool

    var collapseProgress: CGFloat {
        CGFloat(collapseStep) / CGFloat(TVDetailHeroChromeLayout.visualStepCount)
    }
}

struct TVDetailHeroChromeLayout: Equatable {
    static let visualStepCount = 16
    static let heroShadowRadius: CGFloat = 40
    static let heroShadowYOffset: CGFloat = 24

    private static let scrollTopSlop: CGFloat = 14
    private static let previewInteractionThreshold: CGFloat = 0.08

    let collapseProgress: CGFloat

    static func presentation(
        offsetY: CGFloat,
        topInset: CGFloat,
        topTriggerDistance: CGFloat,
        forcedCollapseProgress: CGFloat? = nil
    ) -> TVDetailHeroChromePresentation {
        let rawProgress: CGFloat
        if let forcedCollapseProgress {
            rawProgress = clampedProgress(forcedCollapseProgress)
        } else {
            let effectiveOffset = max(0, offsetY + topInset - scrollTopSlop)
            rawProgress = clampedProgress(effectiveOffset / max(topTriggerDistance, 1))
        }

        return TVDetailHeroChromePresentation(
            collapseStep: min(
                max(Int((rawProgress * CGFloat(visualStepCount)).rounded()), 0),
                visualStepCount
            ),
            previewInteractionEnabled: rawProgress < previewInteractionThreshold
        )
    }

    var outerHorizontalPadding: CGFloat {
        28 * (1 - normalizedProgress)
    }

    var cornerRadius: CGFloat {
        44 * (1 - normalizedProgress)
    }

    var strokeOpacity: Double {
        Double(0.12 * (1 - normalizedProgress))
    }

    private var normalizedProgress: CGFloat {
        let clampedProgress = min(max(collapseProgress, 0), 1)
        return clampedProgress * clampedProgress * (3 - (2 * clampedProgress))
    }

    private static func clampedProgress(_ progress: CGFloat) -> CGFloat {
        min(max(progress, 0), 1)
    }
}
