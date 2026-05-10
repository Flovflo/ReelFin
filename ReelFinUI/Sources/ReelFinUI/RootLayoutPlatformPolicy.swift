enum RootLayoutPlatformPolicy {
    static func shouldUseMacRootLayout(
        isScreenshotMode: Bool,
        isMacCatalyst: Bool
    ) -> Bool {
        !isScreenshotMode && isMacCatalyst
    }

    static func shouldUseSplitLayout(
        isScreenshotMode: Bool,
        isRegularHorizontalSizeClass: Bool,
        isPadIdiom: Bool,
        isMacCatalyst: Bool
    ) -> Bool {
        guard !isScreenshotMode else { return false }
        guard !isMacCatalyst else { return false }
        return isPadIdiom && isRegularHorizontalSizeClass
    }

    static var isMacCatalystRuntime: Bool {
#if targetEnvironment(macCatalyst)
        true
#else
        false
#endif
    }
}
