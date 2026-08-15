#!/usr/bin/env swift

import CoreGraphics
import Darwin
import Foundation
import ImageIO

private enum ComparisonError: Error, CustomStringConvertible {
    case invalidArguments
    case unreadableImage(String)
    case dimensionMismatch(expected: String, actual: String)
    case excessiveChannelDelta(actual: Int, maximum: Int)
    case excessiveChangedFraction(actual: Double, maximum: Double)
    case excessiveComponent(actual: Int, maximum: Int)

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: compare_storefront_png.swift FIRST.png SECOND.png"
        case let .unreadableImage(path):
            return "cannot decode PNG at \(path)"
        case let .dimensionMismatch(expected, actual):
            return "storefront screenshot dimensions differ: \(expected) != \(actual)"
        case let .excessiveChannelDelta(actual, maximum):
            return "storefront screenshot max channel delta \(actual) exceeds \(maximum)"
        case let .excessiveChangedFraction(actual, maximum):
            return "storefront screenshot changed fraction \(actual) exceeds \(maximum)"
        case let .excessiveComponent(actual, maximum):
            return "storefront screenshot connected component \(actual) px exceeds \(maximum) px"
        }
    }
}

private struct DecodedImage {
    let width: Int
    let height: Int
    let rgba: [UInt8]
}

private struct ComparisonMetrics {
    let changedPixels: Int
    let maxChannelDelta: Int
    let componentCount: Int
    let largestComponent: Int
}

private enum StorefrontComparisonPolicy {
    // These limits qualify two candidate acquisitions only. They never replace
    // the bit-exact screenshots.sha256 check for promoted canonical assets.
    static let maxChannelDelta = 1
    static let maxChangedPixelFraction = 0.0001
    static let maxConnectedComponentPixels = 4
}

private func decodeImage(at path: String) throws -> DecodedImage {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ComparisonError.unreadableImage(path)
    }

    let width = image.width
    let height = image.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &rgba,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw ComparisonError.unreadableImage(path)
    }
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return DecodedImage(width: width, height: height, rgba: rgba)
}

private func measure(first: DecodedImage, second: DecodedImage) -> ComparisonMetrics {
    let pixelCount = first.width * first.height
    var changed = [Bool](repeating: false, count: pixelCount)
    var changedPixels = 0
    var maxChannelDelta = 0

    for pixel in 0..<pixelCount {
        let offset = pixel * 4
        var pixelChanged = false
        for channel in 0..<4 {
            let delta = abs(Int(first.rgba[offset + channel]) - Int(second.rgba[offset + channel]))
            maxChannelDelta = max(maxChannelDelta, delta)
            pixelChanged = pixelChanged || delta != 0
        }
        if pixelChanged {
            changed[pixel] = true
            changedPixels += 1
        }
    }

    var componentCount = 0
    var largestComponent = 0
    var stack: [Int] = []
    for origin in 0..<pixelCount where changed[origin] {
        componentCount += 1
        changed[origin] = false
        stack.append(origin)
        var componentSize = 0

        while let pixel = stack.popLast() {
            componentSize += 1
            let x = pixel % first.width
            let y = pixel / first.width
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let neighborX = x + dx
                    let neighborY = y + dy
                    guard neighborX >= 0, neighborX < first.width,
                          neighborY >= 0, neighborY < first.height else { continue }
                    let neighbor = neighborY * first.width + neighborX
                    if changed[neighbor] {
                        changed[neighbor] = false
                        stack.append(neighbor)
                    }
                }
            }
        }
        largestComponent = max(largestComponent, componentSize)
    }

    return ComparisonMetrics(
        changedPixels: changedPixels,
        maxChannelDelta: maxChannelDelta,
        componentCount: componentCount,
        largestComponent: largestComponent
    )
}

private func compare(arguments: [String]) throws {
    guard arguments.count == 3 else { throw ComparisonError.invalidArguments }
    let first = try decodeImage(at: arguments[1])
    let second = try decodeImage(at: arguments[2])
    guard first.width == second.width, first.height == second.height else {
        throw ComparisonError.dimensionMismatch(
            expected: "\(first.width)x\(first.height)",
            actual: "\(second.width)x\(second.height)"
        )
    }

    let metrics = measure(first: first, second: second)
    let changedFraction = Double(metrics.changedPixels) / Double(first.width * first.height)
    let summary = String(
        format: "dimensions=%dx%d changed_pixels=%d changed_fraction=%.9f max_channel_delta=%d components=%d largest_component=%d",
        first.width,
        first.height,
        metrics.changedPixels,
        changedFraction,
        metrics.maxChannelDelta,
        metrics.componentCount,
        metrics.largestComponent
    )
    print(summary)

    guard metrics.maxChannelDelta <= StorefrontComparisonPolicy.maxChannelDelta else {
        throw ComparisonError.excessiveChannelDelta(
            actual: metrics.maxChannelDelta,
            maximum: StorefrontComparisonPolicy.maxChannelDelta
        )
    }
    guard changedFraction <= StorefrontComparisonPolicy.maxChangedPixelFraction else {
        throw ComparisonError.excessiveChangedFraction(
            actual: changedFraction,
            maximum: StorefrontComparisonPolicy.maxChangedPixelFraction
        )
    }
    guard metrics.largestComponent <= StorefrontComparisonPolicy.maxConnectedComponentPixels else {
        throw ComparisonError.excessiveComponent(
            actual: metrics.largestComponent,
            maximum: StorefrontComparisonPolicy.maxConnectedComponentPixels
        )
    }
}

do {
    try compare(arguments: CommandLine.arguments)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
