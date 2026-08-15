enum RootLayoutPlatformPolicy {
    static func shouldUseMacRootLayout(
        isScreenshotMode: Bool,
        isMacCatalyst: Bool
    ) -> Bool {
        !isScreenshotMode && isMacCatalyst
    }

    static func shouldUseSplitLayout(
        isRegularHorizontalSizeClass: Bool,
        isPadIdiom: Bool,
        isMacCatalyst: Bool
    ) -> Bool {
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
