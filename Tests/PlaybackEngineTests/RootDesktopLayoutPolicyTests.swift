@testable import ReelFinUI
import XCTest

final class RootDesktopLayoutPolicyTests: XCTestCase {
    func testPhoneTabPresentationKeepsSearchSeparatedFromPrimaryTabs() {
        XCTAssertEqual(
            PhoneTabDestination.presentationOrder,
            [.home, .settings, .search]
        )
        XCTAssertEqual(PhoneTabDestination.search.rawValue, 1)
    }

    func testMacCatalystUsesMacRootLayout() {
        XCTAssertTrue(
            RootLayoutPlatformPolicy.shouldUseMacRootLayout(
                isScreenshotMode: false,
                isMacCatalyst: true
            )
        )
    }

    func testMacCatalystDoesNotReuseIPadSplitLayout() {
        XCTAssertFalse(
            RootLayoutPlatformPolicy.shouldUseSplitLayout(
                isScreenshotMode: false,
                isRegularHorizontalSizeClass: false,
                isPadIdiom: false,
                isMacCatalyst: true
            )
        )
    }

    func testScreenshotModeDisablesMacRootLayoutOnMacCatalyst() {
        XCTAssertFalse(
            RootLayoutPlatformPolicy.shouldUseMacRootLayout(
                isScreenshotMode: true,
                isMacCatalyst: true
            )
        )
    }

    func testScreenshotModeDisablesSplitLayoutOnMacCatalyst() {
        XCTAssertFalse(
            RootLayoutPlatformPolicy.shouldUseSplitLayout(
                isScreenshotMode: true,
                isRegularHorizontalSizeClass: false,
                isPadIdiom: false,
                isMacCatalyst: true
            )
        )
    }

    func testIPadUsesSplitLayoutOnlyWhenHorizontallyRegular() {
        XCTAssertTrue(
            RootLayoutPlatformPolicy.shouldUseSplitLayout(
                isScreenshotMode: false,
                isRegularHorizontalSizeClass: true,
                isPadIdiom: true,
                isMacCatalyst: false
            )
        )
        XCTAssertFalse(
            RootLayoutPlatformPolicy.shouldUseSplitLayout(
                isScreenshotMode: false,
                isRegularHorizontalSizeClass: false,
                isPadIdiom: true,
                isMacCatalyst: false
            )
        )
    }
}
