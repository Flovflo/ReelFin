#if os(iOS) || os(tvOS)
import CoreGraphics
import UIKit

enum TransparentImageCropper {
    static func readableLogoImage(
        from image: UIImage,
        alphaThreshold: UInt8 = 24,
        isCancelled: @Sendable () -> Bool = { false }
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        guard let bounds = opaqueBounds(
            in: cgImage,
            alphaThreshold: alphaThreshold,
            isCancelled: isCancelled
        ) else { return nil }
        guard bounds.width >= 4, bounds.height >= 4 else { return nil }
        guard hasReadableLuminance(
            in: cgImage,
            bounds: bounds,
            alphaThreshold: alphaThreshold,
            isCancelled: isCancelled
        ) else { return nil }
        guard let cropBounds = opaqueBounds(
            in: cgImage,
            alphaThreshold: 8,
            isCancelled: isCancelled
        ) else { return nil }

        return croppedImage(from: image, cgImage: cgImage, bounds: cropBounds)
    }

    static func cropTransparentPadding(from image: UIImage, alphaThreshold: UInt8 = 8) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        guard let bounds = opaqueBounds(
            in: cgImage,
            alphaThreshold: alphaThreshold,
            isCancelled: { false }
        ) else { return image }

        return croppedImage(from: image, cgImage: cgImage, bounds: bounds)
    }

    private static func croppedImage(from image: UIImage, cgImage: CGImage, bounds: CGRect) -> UIImage {
        let fullBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        guard bounds != fullBounds, let cropped = cgImage.cropping(to: bounds) else {
            return image
        }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func opaqueBounds(
        in cgImage: CGImage,
        alphaThreshold: UInt8,
        isCancelled: @Sendable () -> Bool
    ) -> CGRect? {
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            guard !isCancelled() else { return nil }
            for x in 0..<width {
                let alpha = pixels[((y * width) + x) * 4 + 3]
                guard alpha > alphaThreshold else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func hasReadableLuminance(
        in cgImage: CGImage,
        bounds: CGRect,
        alphaThreshold: UInt8,
        isCancelled: @Sendable () -> Bool
    ) -> Bool {
        guard let cropped = cgImage.cropping(to: bounds) else { return false }
        let width = cropped.width
        let height = cropped.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context else { return false }

        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        var visiblePixelCount = 0
        var brightPixelCount = 0

        for y in 0..<height {
            guard !isCancelled() else { return false }
            let rowStart = y * width * 4
            for x in 0..<width {
                let index = rowStart + (x * 4)
                guard pixels[index + 3] > alphaThreshold else { continue }
                visiblePixelCount += 1
                let luminance = (0.2126 * Double(pixels[index]))
                    + (0.7152 * Double(pixels[index + 1]))
                    + (0.0722 * Double(pixels[index + 2]))
                if luminance > 90 {
                    brightPixelCount += 1
                }
            }
        }

        guard visiblePixelCount > 0 else { return false }
        return brightPixelCount >= max(8, visiblePixelCount / 20)
    }
}
#endif
