import CoreGraphics

#if os(iOS)
enum IOSDetailSynopsisLayout {
    static func lineLimit(isExpanded: Bool, contentWidth: CGFloat) -> Int {
        let isCompact = contentWidth < 370

        if isExpanded {
            return isCompact ? 6 : 8
        }

        return isCompact ? 2 : 3
    }

    static func maximumHeight(fontSize: CGFloat, lineLimit: Int) -> CGFloat {
        ceil(fontSize * 1.34 * CGFloat(max(lineLimit, 1)))
    }

    static func needsExpansion(_ text: String, contentWidth: CGFloat) -> Bool {
        let collapsedLimit = lineLimit(isExpanded: false, contentWidth: contentWidth)
        let approximateCharactersPerLine = max(Int(contentWidth / 8.8), 24)
        return text.count > approximateCharactersPerLine * collapsedLimit
    }
}
#endif
