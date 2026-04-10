import CoreGraphics

enum IOSDetailCarouselLayout {
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

    private static func usesCompactLayout(for viewportWidth: CGFloat) -> Bool {
        viewportWidth < 430
    }
}
