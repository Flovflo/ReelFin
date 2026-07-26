import Foundation
@testable import ImageCache
import UIKit
import XCTest

final class ImageDecodeSchedulerTests: XCTestCase {
    func testRunsAtMostTwoBodiesAndAdmitsOneForOne() async throws {
        let probe = BlockingDecodeProbe()
        let scheduler = ImageDecodeScheduler { data, _ in
            probe.run(id: Int(data[0]))
            return UIImage()
        }
        let tasks = (1 ... 5).map { id in
            Task { try await scheduler.decode(data: Data([UInt8(id)]), maxPixelSize: 320) }
        }

        await probe.waitUntilStarted(count: 2)
        XCTAssertEqual(probe.startedIDs.count, 2)
        XCTAssertEqual(probe.maximumActiveCount, 2)

        probe.release(id: probe.startedIDs[0])
        await probe.waitUntilStarted(count: 3)
        XCTAssertEqual(probe.startedIDs.count, 3)
        XCTAssertEqual(probe.maximumActiveCount, 2)

        probe.releaseAll()
        for task in tasks {
            _ = try await task.value
        }
        XCTAssertEqual(probe.maximumActiveCount, 2)
    }

    func testCancellationBeforeStartPreventsBodyExecution() async throws {
        let probe = BlockingDecodeProbe()
        let scheduler = ImageDecodeScheduler { data, _ in
            probe.run(id: Int(data[0]))
            return UIImage()
        }
        let first = Task { try await scheduler.decode(data: Data([1]), maxPixelSize: 320) }
        let second = Task { try await scheduler.decode(data: Data([2]), maxPixelSize: 320) }
        await probe.waitUntilStarted(count: 2)

        let waiting = Task { try await scheduler.decode(data: Data([3]), maxPixelSize: 320) }
        await waitUntilOperationCount(3, scheduler: scheduler)
        waiting.cancel()
        probe.releaseAll()

        _ = try await first.value
        _ = try await second.value
        do {
            _ = try await waiting.value
            XCTFail("Expected queued decode cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertFalse(probe.startedIDs.contains(3))
    }

    func testCancellationWhileRunningRejectsCompletedBodyResult() async {
        let probe = BlockingDecodeProbe()
        let scheduler = ImageDecodeScheduler { data, _ in
            probe.run(id: Int(data[0]))
            return UIImage()
        }
        let task = Task { try await scheduler.decode(data: Data([1]), maxPixelSize: 320) }
        await probe.waitUntilStarted(count: 1)

        task.cancel()
        probe.release(id: 1)

        do {
            _ = try await task.value
            XCTFail("Expected running decode cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(probe.startedIDs, [1])
    }

    func testCancellationBeforeOperationInstallationPreventsBodyExecution() async {
        let probe = BlockingDecodeProbe()
        let scheduler = ImageDecodeScheduler { data, _ in
            probe.run(id: Int(data[0]))
            return UIImage()
        }
        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await scheduler.decode(data: Data([1]), maxPixelSize: 320)
        }

        do {
            _ = try await task.value
            XCTFail("Expected pre-installation cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(probe.startedIDs.isEmpty)
    }

    func testInvalidPayloadReturnsNil() async throws {
        let scheduler = ImageDecodeScheduler()

        let image = try await scheduler.decode(data: Data("not-an-image".utf8), maxPixelSize: 320)

        XCTAssertNil(image)
    }

    func testNilResultReleasesPermitForNextOperation() async throws {
        let probe = BlockingDecodeProbe()
        let scheduler = ImageDecodeScheduler { data, _ in
            let id = Int(data[0])
            if id == 1 {
                probe.recordImmediateBody(id: id)
                return nil
            }
            probe.run(id: id)
            return UIImage()
        }
        let second = Task { try await scheduler.decode(data: Data([2]), maxPixelSize: 320) }
        await probe.waitUntilStarted(count: 1)
        let first = Task { try await scheduler.decode(data: Data([1]), maxPixelSize: 320) }
        await probe.waitUntilStarted(count: 2)
        let third = Task { try await scheduler.decode(data: Data([3]), maxPixelSize: 320) }

        await probe.waitUntilStarted(count: 3)
        XCTAssertEqual(probe.maximumActiveCount, 2)
        let firstImage = try await first.value
        XCTAssertNil(firstImage)

        probe.releaseAll()
        _ = try await second.value
        _ = try await third.value
    }

    private func waitUntilOperationCount(
        _ expectedCount: Int,
        scheduler: ImageDecodeScheduler
    ) async {
        while scheduler.operationCount < expectedCount {
            await Task.yield()
        }
    }
}

private final class BlockingDecodeProbe: @unchecked Sendable {
    private struct StartWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let condition = NSCondition()
    private var startedStorage = [Int]()
    private var activeCount = 0
    private var maximumActiveCountStorage = 0
    private var releasedIDs = Set<Int>()
    private var releasesAll = false
    private var startWaiters = [StartWaiter]()

    var startedIDs: [Int] {
        condition.withLock { startedStorage }
    }

    var maximumActiveCount: Int {
        condition.withLock { maximumActiveCountStorage }
    }

    func run(id: Int) {
        recordStart(id: id)
        condition.lock()
        while !releasesAll, !releasedIDs.contains(id) {
            condition.wait()
        }
        activeCount -= 1
        condition.unlock()
    }

    func recordImmediateBody(id: Int) {
        recordStart(id: id)
        condition.withLock {
            activeCount -= 1
        }
    }

    func waitUntilStarted(count: Int) async {
        if condition.withLock({ startedStorage.count >= count }) {
            return
        }
        await withCheckedContinuation { continuation in
            let resumeImmediately = condition.withLock {
                guard startedStorage.count < count else { return true }
                startWaiters.append(StartWaiter(count: count, continuation: continuation))
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func release(id: Int) {
        condition.withLock {
            releasedIDs.insert(id)
            condition.broadcast()
        }
    }

    func releaseAll() {
        condition.withLock {
            releasesAll = true
            condition.broadcast()
        }
    }

    private func recordStart(id: Int) {
        let resumptions = condition.withLock {
            startedStorage.append(id)
            activeCount += 1
            maximumActiveCountStorage = max(maximumActiveCountStorage, activeCount)
            let ready = startWaiters.filter { $0.count <= startedStorage.count }
            startWaiters.removeAll { $0.count <= startedStorage.count }
            return ready.map(\.continuation)
        }
        resumptions.forEach { $0.resume() }
    }
}

private extension NSCondition {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
