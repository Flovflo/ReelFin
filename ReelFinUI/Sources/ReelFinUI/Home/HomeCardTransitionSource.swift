enum HomeCardTransitionSource {
    static func id(rowID: String, itemID: String, occurrenceID: String? = nil) -> String {
        if let occurrenceID {
            return "\(rowID)::\(occurrenceID)::\(itemID)"
        }

        return "\(rowID)::\(itemID)"
    }
}

enum HomeFeaturedTransitionSource {
    static func id(itemID: String) -> String {
        "featured::\(itemID)"
    }
}
