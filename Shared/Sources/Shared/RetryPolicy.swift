import Foundation

public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var initialDelayNanoseconds: UInt64
    public var multiplier: Double
    public var jitter: Double

    public init(
        maxRetries: Int = 3,
        initialDelayNanoseconds: UInt64 = 300_000_000,
        multiplier: Double = 2,
        jitter: Double = 0.15
    ) {
        self.maxRetries = maxRetries
        self.initialDelayNanoseconds = initialDelayNanoseconds
        self.multiplier = multiplier
        self.jitter = jitter
    }

    public func delay(for attempt: Int) -> UInt64 {
        let exponent = pow(multiplier, Double(attempt))
        let base = Double(initialDelayNanoseconds) * exponent
        let jitterMultiplier = 1 + Double.random(in: -jitter ... jitter)
        return UInt64(max(50_000_000, base * jitterMultiplier))
    }
}

public func retrying<T>(
    policy: RetryPolicy,
    shouldRetry: @escaping (Error) -> Bool = { _ in true },
    operation: @escaping () async throws -> T
) async throws -> T {
    var currentAttempt = 0
    while true {
        do {
            return try await operation()
        } catch {
            guard currentAttempt < policy.maxRetries, shouldRetry(error) else {
                throw error
            }
            let delay = policy.delay(for: currentAttempt)
            try await Task.sleep(nanoseconds: delay)
            currentAttempt += 1
        }
    }
}
