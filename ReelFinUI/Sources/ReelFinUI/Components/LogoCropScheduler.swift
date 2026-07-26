import Foundation
import UIKit

final class LogoCropScheduler: @unchecked Sendable {
    typealias CancellationCheck = @Sendable () -> Bool
    typealias CropBody = @Sendable (UIImage, CancellationCheck) -> UIImage?

    static let shared = LogoCropScheduler()

    private let queue: OperationQueue
    private let cropBody: CropBody

    var operationCount: Int {
        queue.operationCount
    }

    init(cropBody: @escaping CropBody = { image, isCancelled in
        TransparentImageCropper.readableLogoImage(
            from: image,
            isCancelled: isCancelled
        )
    }) {
        let queue = OperationQueue()
        queue.name = "com.reelfin.logo-crop"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        self.queue = queue
        self.cropBody = cropBody
    }

    func crop(_ image: UIImage) async throws -> UIImage? {
        let request = LogoCropRequest()
        let croppedImage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let operation = LogoCropOperation(
                    image: image,
                    cropBody: cropBody
                )
                operation.completionBlock = { [weak operation, request] in
                    request.complete(with: operation?.croppedImage)
                }
                request.install(operation: operation, continuation: continuation)
                queue.addOperation(operation)
            }
        } onCancel: {
            request.cancel()
        }

        try Task.checkCancellation()
        return croppedImage
    }
}

private final class LogoCropOperation: Operation, @unchecked Sendable {
    private let image: UIImage
    private let cropBody: LogoCropScheduler.CropBody
    private let resultLock = NSLock()
    private var croppedImageStorage: UIImage?

    var croppedImage: UIImage? {
        resultLock.lock()
        defer { resultLock.unlock() }
        return croppedImageStorage
    }

    init(image: UIImage, cropBody: @escaping LogoCropScheduler.CropBody) {
        self.image = image
        self.cropBody = cropBody
        super.init()
    }

    override func main() {
        guard !isCancelled else { return }
        let croppedImage = cropBody(image) { [weak self] in
            self?.isCancelled ?? true
        }
        guard !isCancelled else { return }

        resultLock.lock()
        croppedImageStorage = croppedImage
        resultLock.unlock()
    }
}

private final class LogoCropRequest: @unchecked Sendable {
    typealias Continuation = CheckedContinuation<UIImage?, Error>

    private let lock = NSLock()
    private var continuation: Continuation?
    private var operation: Operation?
    private var cancellationRequested = false
    private var isFinished = false

    func install(operation: Operation, continuation: Continuation) {
        lock.lock()
        self.operation = operation
        if cancellationRequested {
            isFinished = true
            self.operation = nil
            lock.unlock()
            operation.cancel()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let installedOperation = operation
        operation = nil
        let installedContinuation: Continuation?
        if isFinished {
            installedContinuation = nil
        } else {
            isFinished = true
            installedContinuation = continuation
            continuation = nil
        }
        lock.unlock()

        installedOperation?.cancel()
        installedContinuation?.resume(throwing: CancellationError())
    }

    func complete(with image: UIImage?) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        operation = nil
        let installedContinuation = continuation
        continuation = nil
        lock.unlock()

        installedContinuation?.resume(returning: image)
    }
}
