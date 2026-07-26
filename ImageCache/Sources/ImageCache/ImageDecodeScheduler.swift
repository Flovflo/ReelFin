import Foundation
import ImageIO
import UIKit

final class ImageDecodeScheduler: @unchecked Sendable {
    typealias DecodeBody = @Sendable (Data, Int) -> UIImage?

    private let queue: OperationQueue
    private let decodeBody: DecodeBody

    var operationCount: Int {
        queue.operationCount
    }

    init(decodeBody: @escaping DecodeBody = ImageDecodeScheduler.decodeImage) {
        let queue = OperationQueue()
        queue.name = "com.reelfin.image-decode"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        self.queue = queue
        self.decodeBody = decodeBody
    }

    func decode(data: Data, maxPixelSize: Int) async throws -> UIImage? {
        let handle = DecodeOperationHandle()
        let image = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let operation = DecodeOperation(
                    data: data,
                    maxPixelSize: maxPixelSize,
                    decodeBody: decodeBody
                )
                operation.completionBlock = { [weak operation] in
                    continuation.resume(returning: operation?.decodedImage)
                }
                handle.install(operation)
                queue.addOperation(operation)
            }
        } onCancel: {
            handle.cancel()
        }

        try Task.checkCancellation()
        return image
    }

    private static func decodeImage(data: Data, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: cgImage)
        }

        return UIImage(data: data)
    }
}

private final class DecodeOperation: Operation, @unchecked Sendable {
    private let data: Data
    private let maxPixelSize: Int
    private let decodeBody: ImageDecodeScheduler.DecodeBody
    private let resultLock = NSLock()
    private var decodedImageStorage: UIImage?

    var decodedImage: UIImage? {
        resultLock.withLock { decodedImageStorage }
    }

    init(
        data: Data,
        maxPixelSize: Int,
        decodeBody: @escaping ImageDecodeScheduler.DecodeBody
    ) {
        self.data = data
        self.maxPixelSize = maxPixelSize
        self.decodeBody = decodeBody
        super.init()
    }

    override func main() {
        guard !isCancelled else { return }
        let image = decodeBody(data, maxPixelSize)
        guard !isCancelled else { return }
        resultLock.withLock {
            decodedImageStorage = image
        }
    }
}

private final class DecodeOperationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var operation: Operation?
    private var cancellationRequested = false

    func install(_ operation: Operation) {
        let shouldCancel = lock.withLock {
            self.operation = operation
            return cancellationRequested
        }
        if shouldCancel {
            operation.cancel()
        }
    }

    func cancel() {
        let installedOperation = lock.withLock {
            cancellationRequested = true
            return operation
        }
        installedOperation?.cancel()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
