import Shared

struct TVHomeRowFocusContext: Equatable {
    let rowID: String
    let itemIndex: Int
}

enum TVHomeFocusDirection {
    case up
    case down
}

struct TVHomeFocusPolicy: Equatable {
    static let heroPlayFocusID = "home.featured.play"

    private let rows: [HomeRow]

    init(rows: [HomeRow]) {
        self.rows = rows.filter { !$0.items.isEmpty }
    }

    func entryFocusID(
        returnTarget: TVHomeReturnTarget?,
        hasFeaturedContent: Bool
    ) -> String? {
        switch returnTarget {
        case let .row(_, itemID):
            return containsItem(withID: itemID) ? itemID : fallbackEntryFocusID(hasFeaturedContent: hasFeaturedContent)
        case .featured:
            return hasFeaturedContent ? Self.heroPlayFocusID : firstRowItemID
        case .none:
            return fallbackEntryFocusID(hasFeaturedContent: hasFeaturedContent)
        }
    }

    func targetFocusID(
        from context: TVHomeRowFocusContext,
        direction: TVHomeFocusDirection,
        hasFeaturedContent: Bool
    ) -> String? {
        guard let rowIndex = rows.firstIndex(where: { $0.id == context.rowID }) else {
            return nil
        }

        switch direction {
        case .up:
            if rowIndex == 0 {
                return hasFeaturedContent ? Self.heroPlayFocusID : nil
            }
            return itemID(in: rows[rowIndex - 1], preferredIndex: context.itemIndex)
        case .down:
            let nextIndex = rowIndex + 1
            guard rows.indices.contains(nextIndex) else { return nil }
            return itemID(in: rows[nextIndex], preferredIndex: context.itemIndex)
        }
    }

    var firstRowItemID: String? {
        rows.first?.items.first?.id
    }

    private func fallbackEntryFocusID(hasFeaturedContent: Bool) -> String? {
        if hasFeaturedContent {
            return Self.heroPlayFocusID
        }
        return firstRowItemID
    }

    private func containsItem(withID itemID: String) -> Bool {
        rows.contains { row in
            row.items.contains(where: { $0.id == itemID })
        }
    }

    private func itemID(in row: HomeRow, preferredIndex: Int) -> String? {
        guard !row.items.isEmpty else { return nil }
        let clampedIndex = min(max(preferredIndex, 0), row.items.count - 1)
        return row.items[clampedIndex].id
    }
}
