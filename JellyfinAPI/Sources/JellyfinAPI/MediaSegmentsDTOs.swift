import Foundation
import Shared

struct MediaSegmentQueryResultDTO: Decodable {
    let items: [MediaSegmentDTO]

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? container.decodeIfPresent(LossyArray<MediaSegmentDTO>.self, forKey: .items))?.elements ?? []
    }
}

struct MediaSegmentDTO: Decodable {
    let id: String?
    let itemID: String?
    let type: String?
    let startTicks: Int64?
    let endTicks: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case itemID = "ItemId"
        case type = "Type"
        case startTicks = "StartTicks"
        case endTicks = "EndTicks"
    }

    func toDomain(defaultItemID: String) -> MediaSegment? {
        guard
            let type,
            let startTicks,
            let endTicks
        else {
            return nil
        }

        let resolvedItemID = itemID ?? defaultItemID
        let resolvedID = id ?? "\(resolvedItemID)-\(type)-\(startTicks)"
        return MediaSegment(
            id: resolvedID,
            itemID: resolvedItemID,
            type: MediaSegmentType(jellyfinValue: type),
            startTicks: startTicks,
            endTicks: endTicks
        )
    }
}
