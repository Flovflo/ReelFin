import Foundation

public actor DetailPresentationTelemetry {
    public static let shared = DetailPresentationTelemetry()
    private static let staleEntryAge: TimeInterval = 30

    private struct Entry {
        let startDate: Date
        var detailVisibleLogged = false
        var heroVisibleLogged = false
        var metadataReadyLogged = false
        var playReadyLogged = false
    }

    private var entries: [String: Entry] = [:]

    @discardableResult
    public func beginNavigation(for itemID: String) -> Bool {
        let now = Date()
        entries = entries.filter { now.timeIntervalSince($0.value.startDate) < Self.staleEntryAge }
        guard entries[itemID] == nil else { return false }

        entries[itemID] = Entry(startDate: now)
        AppLog.ui.notice("Detail navigation started for \(itemID, privacy: .public)")
        return true
    }

    public func endNavigation(for itemID: String) {
        entries[itemID] = nil
    }

    public func markDetailVisible(for itemID: String) {
        guard var entry = entries[itemID], !entry.detailVisibleLogged else { return }
        entry.detailVisibleLogged = true
        entries[itemID] = entry
        log(label: "detail_visible", itemID: itemID, from: entry.startDate)
    }

    public func markHeroVisible(for itemID: String) {
        guard var entry = entries[itemID], !entry.heroVisibleLogged else { return }
        entry.heroVisibleLogged = true
        entries[itemID] = entry
        log(label: "hero_visible", itemID: itemID, from: entry.startDate)
    }

    public func markMetadataReady(for itemID: String) {
        guard var entry = entries[itemID], !entry.metadataReadyLogged else { return }
        entry.metadataReadyLogged = true
        entries[itemID] = entry
        log(label: "metadata_ready", itemID: itemID, from: entry.startDate)
    }

    public func markPlayReady(for itemID: String) {
        guard var entry = entries[itemID], !entry.playReadyLogged else { return }
        entry.playReadyLogged = true
        entries[itemID] = entry
        log(label: "play_ready", itemID: itemID, from: entry.startDate)
    }

    private func log(label: String, itemID: String, from startDate: Date) {
        let elapsedMs = Int(Date().timeIntervalSince(startDate) * 1000)
        AppLog.ui.notice("Detail telemetry \(label, privacy: .public) for \(itemID, privacy: .public): \(elapsedMs, privacy: .public)ms")
    }
}
