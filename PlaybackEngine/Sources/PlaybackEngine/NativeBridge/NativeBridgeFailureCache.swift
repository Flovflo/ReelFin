import Foundation

enum NativeBridgeFailureCache {
    private static let storageKey = "reelfin.nativebridge.disabled.items"
    private static let ttl: TimeInterval = 24 * 60 * 60

    static func isDisabled(itemID: String, now: Date = Date()) -> Bool {
        clearExpired(now: now)
        let map = load()
        guard let expiry = map[itemID] else { return false }
        return now.timeIntervalSince1970 < expiry
    }

    static func recordFailure(itemID: String, now: Date = Date()) {
        var map = load()
        map[itemID] = now.timeIntervalSince1970 + ttl
        save(map)
    }

    static func clearFailure(itemID: String) {
        var map = load()
        map.removeValue(forKey: itemID)
        save(map)
    }

    private static func clearExpired(now: Date) {
        let nowTime = now.timeIntervalSince1970
        let trimmed = load().filter { $0.value > nowTime }
        save(trimmed)
    }

    private static func load() -> [String: TimeInterval] {
        guard let raw = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: TimeInterval] else {
            return [:]
        }
        return raw
    }

    private static func save(_ map: [String: TimeInterval]) {
        UserDefaults.standard.set(map, forKey: storageKey)
    }
}
