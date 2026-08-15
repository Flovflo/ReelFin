#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum StorefrontPNGError: Error, CustomStringConvertible {
    case invalidArguments
    case unreadableImage(String)
    case unexpectedDimensions(expected: String, actual: String)
    case cannotCreateRGBContext
    case cannotCreateDestination(String)
    case cannotWriteImage(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: prepare_storefront_png.swift INPUT OUTPUT WIDTH HEIGHT"
        case .unreadableImage(let path):
            return "cannot decode PNG at \(path)"
        case .unexpectedDimensions(let expected, let actual):
            return "expected \(expected), found \(actual)"
        case .cannotCreateRGBContext:
            return "cannot allocate an opaque RGB bitmap"
        case .cannotCreateDestination(let path):
            return "cannot create PNG destination at \(path)"
        case .cannotWriteImage(let path):
            return "cannot write PNG at \(path)"
        }
    }
}

func prepareStorefrontPNG(arguments: [String]) throws {
    guard arguments.count == 5,
          let expectedWidth = Int(arguments[3]),
          let expectedHeight = Int(arguments[4]) else {
        throw StorefrontPNGError.invalidArguments
    }

    let inputPath = arguments[1]
    let outputPath = arguments[2]
    let inputURL = URL(fileURLWithPath: inputPath)
    let outputURL = URL(fileURLWithPath: outputPath)

    guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw StorefrontPNGError.unreadableImage(inputPath)
    }

    guard image.width == expectedWidth, image.height == expectedHeight else {
        throw StorefrontPNGError.unexpectedDimensions(
            expected: "\(expectedWidth)x\(expectedHeight)",
            actual: "\(image.width)x\(image.height)"
        )
    }

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        throw StorefrontPNGError.cannotCreateRGBContext
    }

    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

    guard let opaqueImage = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              outputURL as CFURL,
              UTType.png.identifier as CFString,
              1,
              nil
          ) else {
        throw StorefrontPNGError.cannotCreateDestination(outputPath)
    }

    CGImageDestinationAddImage(destination, opaqueImage, [
        kCGImagePropertyPNGInterlaceType: 0,
        kCGImageDestinationLossyCompressionQuality: 1
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw StorefrontPNGError.cannotWriteImage(outputPath)
    }
}

do {
    try prepareStorefrontPNG(arguments: CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
