import Shared
import SwiftUI
import UIKit

struct TVTopNavigationAppearance: Equatable, Sendable {
    struct RGB: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(_ color: UIColor) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            self.init(red: Double(red), green: Double(green), blue: Double(blue))
        }

        func mixed(with other: RGB, amount: Double) -> RGB {
            let ratio = min(max(amount, 0), 1)
            return RGB(
                red: red + ((other.red - red) * ratio),
                green: green + ((other.green - green) * ratio),
                blue: blue + ((other.blue - blue) * ratio)
            )
        }

        func color(opacity: Double = 1) -> Color {
            Color(
                uiColor: UIColor(
                    red: CGFloat(red),
                    green: CGFloat(green),
                    blue: CGFloat(blue),
                    alpha: CGFloat(opacity)
                )
            )
        }

        static let white = RGB(red: 1, green: 1, blue: 1)
    }

    let railTint: RGB
    let highlightTint: RGB
    let backdropOpacity: Double

    static let neutral = TVTopNavigationAppearance(
        railTint: RGB(red: 0.34, green: 0.27, blue: 0.15),
        highlightTint: RGB(red: 0.97, green: 0.94, blue: 0.90),
        backdropOpacity: 0.16
    )

    static func fallback(for item: MediaItem) -> TVTopNavigationAppearance {
        let seed = stableSeed(for: item)
        let hue = CGFloat(seed % 360) / 360
        let rail = UIColor(hue: hue, saturation: 0.45, brightness: 0.42, alpha: 1)
        let highlight = UIColor(hue: hue, saturation: 0.20, brightness: 0.95, alpha: 1)
        return TVTopNavigationAppearance(
            railTint: RGB(rail),
            highlightTint: RGB(highlight),
            backdropOpacity: 0.20
        )
    }

    var railGlassTint: Color { railTint.color(opacity: 0.30) }
    var railGlowColor: Color { railTint.mixed(with: .white, amount: 0.12).color(opacity: 0.18) }
    var railStrokeColor: Color { railTint.mixed(with: .white, amount: 0.48).color(opacity: 0.20) }
    var highlightBaseColor: Color { highlightTint.color(opacity: 0.96) }
    var highlightGlowColor: Color { highlightTint.mixed(with: .white, amount: 0.25).color(opacity: 0.48) }
    var highlightGlassTint: Color { railTint.mixed(with: highlightTint, amount: 0.35).color(opacity: 0.24) }
    var highlightLabelColor: Color { Color(red: 0.09, green: 0.10, blue: 0.12) }

    private static func stableSeed(for item: MediaItem) -> Int {
        let source = "\(item.name)|\(item.year ?? 0)|\(item.mediaType.rawValue)"
        return source.unicodeScalars.reduce(0) { partialResult, scalar in
            ((partialResult * 33) + Int(scalar.value)) % 10_000
        }
    }
}
