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
                isRegularHorizontalSizeClass: false,
                isPadIdiom: false,
                isMacCatalyst: true
            )
        )
    }

    func testRegularIPadUsesSplitLayoutIncludingStorefrontCaptureMode() {
        XCTAssertTrue(
            RootLayoutPlatformPolicy.shouldUseSplitLayout(
                isRegularHorizontalSizeClass: true,
                isPadIdiom: true,
                isMacCatalyst: false
            )
        )
        XCTAssertFalse(
            RootLayoutPlatformPolicy.shouldUseSplitLayout(
                isRegularHorizontalSizeClass: false,
                isPadIdiom: true,
                isMacCatalyst: false
            )
        )
    }

    func testPhoneNeverUsesIPadSplitLayout() {
        XCTAssertFalse(
            RootLayoutPlatformPolicy.shouldUseSplitLayout(
                isRegularHorizontalSizeClass: true,
                isPadIdiom: false,
                isMacCatalyst: false
            )
        )
    }
}
