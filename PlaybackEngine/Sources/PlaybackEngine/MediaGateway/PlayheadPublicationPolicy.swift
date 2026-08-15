import Foundation

struct PlayheadPublication: Sendable {
    let revision: UInt64
    let target: Int64?
}

final class PlayheadPublicationPolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var latestRevision: UInt64 = 0

    func record(target: Int64?) -> PlayheadPublication {
        lock.withLock {
            latestRevision &+= 1
            return PlayheadPublication(revision: latestRevision, target: target)
        }
    }

    func shouldDeliver(_ publication: PlayheadPublication) -> Bool {
        lock.withLock { publication.revision == latestRevision }
    }
}

actor PlayheadPublicationCoordinator {
    private let deliver: @Sendable (Int64) async -> Void
    private var latestSubmittedRevision: UInt64 = 0
    private var pending: PlayheadPublication?
    private var isDraining = false

    init(
        policy: PlayheadPublicationPolicy,
        deliver: @escaping @Sendable (Int64) async -> Void
    ) {
        _ = policy
        self.deliver = deliver
    }

    func publish(_ publication: PlayheadPublication) async {
        guard publication.revision > latestSubmittedRevision else { return }
        latestSubmittedRevision = publication.revision
        pending = publication.target == nil ? nil : publication
        guard !isDraining else { return }

        isDraining = true
        while let next = pending {
            pending = nil
            if let target = next.target {
                await deliver(target)
            }
        }
        isDraining = false
    }
}

final class PlayheadTargetState<Key: Hashable>: @unchecked Sendable {
    private let lock = NSLock()
    private let policy = PlayheadPublicationPolicy()
    private var entries: [Key: (offset: Int64, waiting: Bool)] = [:]

    func update(key: Key, offset: Int64, waiting: Bool) -> PlayheadPublication {
        lock.withLock {
            entries[key] = (offset, waiting)
            return policy.record(target: targetLocked())
        }
    }

    func remove(key: Key) -> PlayheadPublication {
        lock.withLock {
            entries[key] = nil
            return policy.record(target: targetLocked())
        }
    }

    private func targetLocked() -> Int64? {
        let starved = entries.values.lazy.filter(\.waiting).map(\.offset)
        if let lowestStarved = starved.min() { return lowestStarved }
        return entries.values.lazy.map(\.offset).max()
    }
}

final class TokenTaskRegistry<Key: Hashable>: @unchecked Sendable {
    typealias Work = Task<Void, Never>
    private struct Entry {
        let token: UUID
        var task: Work?
    }
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]

    func reserve(_ key: Key) -> (token: UUID, replacedTask: Work?) {
        lock.withLock {
            let token = UUID()
            let replaced = entries[key]?.task
            entries[key] = Entry(token: token, task: nil)
            return (token, replaced)
        }
    }

    func attach(_ task: Work, key: Key, token: UUID) -> Bool {
        lock.withLock {
            guard entries[key]?.token == token else { return false }
            entries[key]?.task = task
            return true
        }
    }

    func remove(key: Key, token: UUID) -> (removed: Bool, task: Work?) {
        lock.withLock {
            guard entries[key]?.token == token else { return (false, nil) }
            return (true, entries.removeValue(forKey: key)?.task)
        }
    }

    func removeCurrent(key: Key) -> Work? {
        lock.withLock { entries.removeValue(forKey: key)?.task }
    }

    func drain() -> [Work] {
        lock.withLock {
            let tasks = entries.values.compactMap(\.task)
            entries.removeAll()
            return tasks
        }
    }
}
