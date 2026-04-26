#if os(iOS)
import UIKit
import XCTest
@testable import ReelFinUI

final class TransparentImageCropperTests: XCTestCase {
    func testCropsTransparentPaddingAroundLogoArtwork() {
        let image = transparentImageWithOpaqueRect(
            canvasSize: CGSize(width: 100, height: 60),
            opaqueRect: CGRect(x: 30, y: 20, width: 40, height: 16)
        )

        let cropped = TransparentImageCropper.cropTransparentPadding(from: image)

        XCTAssertEqual(cropped.size.width, 40, accuracy: 0.001)
        XCTAssertEqual(cropped.size.height, 16, accuracy: 0.001)
    }

    func testKeepsFullyOpaqueArtworkUnchanged() {
        let image = transparentImageWithOpaqueRect(
            canvasSize: CGSize(width: 32, height: 18),
            opaqueRect: CGRect(x: 0, y: 0, width: 32, height: 18)
        )

        let cropped = TransparentImageCropper.cropTransparentPadding(from: image)

        XCTAssertEqual(cropped.size.width, image.size.width, accuracy: 0.001)
        XCTAssertEqual(cropped.size.height, image.size.height, accuracy: 0.001)
    }

    func testRejectsEmptyLogoArtworkSoTitleTextCanFallback() {
        let image = transparentImageWithOpaqueRect(
            canvasSize: CGSize(width: 100, height: 60),
            opaqueRect: .zero
        )

        XCTAssertNil(TransparentImageCropper.readableLogoImage(from: image))
    }

    func testRejectsTinyLogoArtifactsSoTitleTextCanFallback() {
        let image = transparentImageWithOpaqueRect(
            canvasSize: CGSize(width: 100, height: 60),
            opaqueRect: CGRect(x: 50, y: 30, width: 1, height: 1)
        )

        XCTAssertNil(TransparentImageCropper.readableLogoImage(from: image))
    }

    func testRejectsDarkLogoArtworkSoTitleTextCanFallbackOnDarkHero() {
        let image = transparentImageWithOpaqueRect(
            canvasSize: CGSize(width: 100, height: 60),
            opaqueRect: CGRect(x: 30, y: 20, width: 40, height: 16),
            color: .black
        )

        XCTAssertNil(TransparentImageCropper.readableLogoImage(from: image))
    }

    func testRejectsLowContrastLogoArtworkSoTitleTextCanFallbackOnDarkHero() {
        let image = transparentImageWithOpaqueRect(
            canvasSize: CGSize(width: 100, height: 60),
            opaqueRect: CGRect(x: 30, y: 20, width: 40, height: 16),
            color: UIColor(white: 0.22, alpha: 1)
        )

        XCTAssertNil(TransparentImageCropper.readableLogoImage(from: image))
    }

    private func transparentImageWithOpaqueRect(canvasSize: CGSize, opaqueRect: CGRect) -> UIImage {
        transparentImageWithOpaqueRect(canvasSize: canvasSize, opaqueRect: opaqueRect, color: .white)
    }

    private func transparentImageWithOpaqueRect(canvasSize: CGSize, opaqueRect: CGRect, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            context.cgContext.setFillColor(UIColor.clear.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: canvasSize))
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fill(opaqueRect)
        }
    }
}
#endif
