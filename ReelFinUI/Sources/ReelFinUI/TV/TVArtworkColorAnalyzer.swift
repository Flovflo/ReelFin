import CoreImage
import UIKit

enum TVArtworkColorAnalyzer {
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    static func appearance(
        for image: UIImage,
        fallback: TVTopNavigationAppearance
    ) -> TVTopNavigationAppearance {
        guard let ciImage = CIImage(image: image) else { return fallback }
        guard let filter = CIFilter(name: "CIAreaAverage") else { return fallback }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return fallback }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return appearance(
            from: UIColor(
                red: CGFloat(pixel[0]) / 255,
                green: CGFloat(pixel[1]) / 255,
                blue: CGFloat(pixel[2]) / 255,
                alpha: 1
            ),
            fallback: fallback
        )
    }

    private static func appearance(
        from color: UIColor,
        fallback: TVTopNavigationAppearance
    ) -> TVTopNavigationAppearance {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return fallback
        }

        let rail = UIColor(
            hue: hue,
            saturation: max(0.20, saturation * 0.84),
            brightness: min(0.52, max(0.24, brightness * 0.62)),
            alpha: 1
        )
        let highlight = UIColor(
            hue: hue,
            saturation: max(0.12, saturation * 0.34),
            brightness: min(0.98, max(0.84, brightness * 1.20)),
            alpha: 1
        )
        let backdropOpacity = min(0.28, max(0.14, Double(saturation) * 0.16 + Double(brightness) * 0.08))
        return TVTopNavigationAppearance(
            railTint: .init(rail),
            highlightTint: .init(highlight),
            backdropOpacity: backdropOpacity
        )
    }
}
