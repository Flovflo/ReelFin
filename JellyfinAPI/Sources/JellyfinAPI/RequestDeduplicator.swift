import Foundation

actor RequestDeduplicator {
    private var inFlight: [String: Task<Data, Error>] = [:]

    func data(for key: String, taskFactory: @escaping @Sendable () async throws -> Data) async throws -> Data {
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task {
            try await taskFactory()
        }
        inFlight[key] = task

        do {
            let value = try await task.value
            inFlight[key] = nil
            return value
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func cancelAll() {
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }
}
