import Foundation

public enum TVHeroPagingPolicy {
    public static func contextItems(
        around item: MediaItem,
        in items: [MediaItem]
    ) -> [MediaItem] {
        guard let centerIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return Array(items.prefix(3))
        }

        let lowerBound = max(0, centerIndex - 1)
        let upperBound = min(items.count, centerIndex + 3)
        return Array(items[lowerBound..<upperBound])
    }
}

public enum TVLibraryPaginationPolicy {
    public static func triggerItemID(
        in items: [MediaItem],
        trailingWindow: Int = 12
    ) -> String? {
        guard !items.isEmpty else { return nil }
        let clampedWindow = max(1, trailingWindow)
        let triggerIndex = max(0, items.count - clampedWindow)
        return items[triggerIndex].id
    }
}

public struct DetailNeighborNavigationState: Equatable, Sendable {
    public let currentItem: MediaItem
    public let contextItems: [MediaItem]

    public init(currentItem: MediaItem, contextItems: [MediaItem]) {
        self.currentItem = currentItem
        self.contextItems = contextItems
    }

    public var previousItem: MediaItem? {
        guard let currentIndex, currentIndex > 0 else { return nil }
        return contextItems[currentIndex - 1]
    }

    public var nextItem: MediaItem? {
        guard let currentIndex, currentIndex < contextItems.count - 1 else { return nil }
        return contextItems[currentIndex + 1]
    }

    public var currentIndex: Int? {
        let targetID = currentItem.id
        return contextItems.firstIndex { candidate in
            candidate.id == targetID || candidate.parentID == targetID
        }
    }
}
