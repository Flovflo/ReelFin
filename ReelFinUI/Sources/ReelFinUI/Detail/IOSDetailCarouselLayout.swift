import CoreGraphics

enum IOSDetailCarouselLayout {
    static let verticalScrollLockThreshold: CGFloat = 0.01

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
}
