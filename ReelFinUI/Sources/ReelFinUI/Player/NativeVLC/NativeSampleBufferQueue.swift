import CoreMedia
import Foundation

final class NativeSampleBufferQueue: @unchecked Sendable {
    private let capacity: Int
    private var storage: [CMSampleBuffer?]
    private var head = 0
    private var tail = 0
    private var storedCount = 0
    private var storedDuration: Double = 0
    private let lock = NSLock()

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    var isFull: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedCount == capacity
    }

    func push(_ sample: CMSampleBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard storedCount < capacity else { return false }
        storage[tail] = sample
        tail = (tail + 1) % capacity
        storedCount += 1
        storedDuration += Self.durationSeconds(sample)
        return true
    }

    func pop() -> CMSampleBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard storedCount > 0 else { return nil }
        let sample = storage[head]
        storage[head] = nil
        head = (head + 1) % capacity
        storedCount -= 1
        if let sample {
            storedDuration = max(0, storedDuration - Self.durationSeconds(sample))
        }
        return sample
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage = Array(repeating: nil, count: capacity)
        head = 0
        tail = 0
        storedCount = 0
        storedDuration = 0
    }

    func snapshot() -> NativeSampleBufferQueueSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return NativeSampleBufferQueueSnapshot(
            count: storedCount,
            capacity: capacity,
            durationSeconds: storedDuration
        )
    }

    private static func durationSeconds(_ sample: CMSampleBuffer) -> Double {
        let duration = CMSampleBufferGetDuration(sample)
        guard duration.isValid, !duration.isIndefinite else { return 0 }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }
}

struct NativeSampleBufferQueueSnapshot: Equatable {
    var count: Int
    var capacity: Int
    var durationSeconds: Double
}
