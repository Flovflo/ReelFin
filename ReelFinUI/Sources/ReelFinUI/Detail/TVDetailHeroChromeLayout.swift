import CoreGraphics

struct TVDetailHeroChromeLayout: Equatable {
    let collapseProgress: CGFloat

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
}
