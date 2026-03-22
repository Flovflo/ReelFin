import Foundation

public extension JellyfinImageType {
    func normalizedImageWidth(_ requestedWidth: Int) -> Int {
        let width = max(requestedWidth, 1)
        let buckets = Self.imageWidthBuckets(for: self)
        return buckets.first(where: { width <= $0 }) ?? buckets.last ?? width
    }

    private static func imageWidthBuckets(for type: JellyfinImageType) -> [Int] {
        switch type {
        case .primary:
            return [240, 320, 400, 480, 640, 800, 960, 1280]
        case .backdrop:
            return [640, 800, 960, 1280, 1600, 1920, 2200]
        case .logo:
            return [320, 480, 640, 800, 960]
        }
    }
}
