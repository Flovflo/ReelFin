import Foundation

private actor TVFocusWarmupLimiter {
    private let maxConcurrentJobs: Int
    private var activeJobs = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrentJobs: Int) {
        self.maxConcurrentJobs = max(1, maxConcurrentJobs)
    }

    func acquire() async {
        if activeJobs < maxConcurrentJobs {
            activeJobs += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let nextWaiter = waiters.first {
            waiters.removeFirst()
            nextWaiter.resume()
            return
        }

        activeJobs = max(0, activeJobs - 1)
    }
}

public actor TVFocusWarmupCoordinator {
    public typealias AsyncWork = () async -> Void

    private let settleDelayNanoseconds: UInt64
    private let limiter: TVFocusWarmupLimiter

    private var taskByScope: [String: Task<Void, Never>] = [:]
    private var generationByScope: [String: Int] = [:]

    public init(
        settleDelayNanoseconds: UInt64 = 180_000_000,
        maxConcurrentJobs: Int = 3
    ) {
        self.settleDelayNanoseconds = settleDelayNanoseconds
        self.limiter = TVFocusWarmupLimiter(maxConcurrentJobs: maxConcurrentJobs)
    }

    public func schedule(
        scope: String,
        settleDelayNanoseconds overrideSettleDelayNanoseconds: UInt64? = nil,
        detailShell: AsyncWork? = nil,
        artworkPrefetch: AsyncWork? = nil,
        playbackWarmup: AsyncWork? = nil
    ) {
        taskByScope[scope]?.cancel()

        let generation = (generationByScope[scope] ?? 0) + 1
        generationByScope[scope] = generation

        let delayNanoseconds = overrideSettleDelayNanoseconds ?? settleDelayNanoseconds
        let task = Task(priority: .utility) {
            if delayNanoseconds > 0 {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }
            }

            await self.runScheduledWork(
                scope: scope,
                generation: generation,
                detailShell: detailShell,
                artworkPrefetch: artworkPrefetch,
                playbackWarmup: playbackWarmup
            )
        }
        taskByScope[scope] = task
    }

    public func cancel(scope: String) {
        taskByScope[scope]?.cancel()
        taskByScope[scope] = nil
        generationByScope[scope] = (generationByScope[scope] ?? 0) + 1
    }

    public func cancelAll() {
        for task in taskByScope.values {
            task.cancel()
        }
        taskByScope.removeAll()

        for scope in generationByScope.keys {
            generationByScope[scope] = (generationByScope[scope] ?? 0) + 1
        }
    }

    private func runScheduledWork(
        scope: String,
        generation: Int,
        detailShell: AsyncWork?,
        artworkPrefetch: AsyncWork?,
        playbackWarmup: AsyncWork?
    ) async {
        guard isCurrent(scope: scope, generation: generation) else { return }
        await limiter.acquire()
        defer { Task { await self.limiter.release() } }

        if let detailShell {
            guard !Task.isCancelled, isCurrent(scope: scope, generation: generation) else { return }
            await detailShell()
        }

        if let artworkPrefetch {
            guard !Task.isCancelled, isCurrent(scope: scope, generation: generation) else { return }
            await artworkPrefetch()
        }

        if let playbackWarmup {
            guard !Task.isCancelled, isCurrent(scope: scope, generation: generation) else { return }
            await playbackWarmup()
        }
    }

    private func isCurrent(scope: String, generation: Int) -> Bool {
        generationByScope[scope] == generation
    }
}
