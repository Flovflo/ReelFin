import Foundation

public struct BMFFBoxNode: Sendable, Equatable {
    public let type: String
    public let size: Int
    public let offset: Int

    public init(type: String, size: Int, offset: Int) {
        self.type = type
        self.size = size
        self.offset = offset
    }
}

public enum BMFFValidationError: Error, LocalizedError {
    case truncated(Int)
    case invalidSize(Int)
    case missingTopLevel(String)

    public var errorDescription: String? {
        switch self {
        case .truncated(let offset):
            return "Truncated MP4 box header at offset \(offset)"
        case .invalidSize(let offset):
            return "Invalid MP4 box size at offset \(offset)"
        case .missingTopLevel(let type):
            return "Missing required top-level box: \(type)"
        }
    }
}

public struct BMFFValidator: Sendable {
    public init() {}

    public func parseTopLevelBoxes(_ data: Data) throws -> [BMFFBoxNode] {
        var boxes: [BMFFBoxNode] = []
        var offset = 0

        while offset < data.count {
            guard offset + 8 <= data.count else {
                throw BMFFValidationError.truncated(offset)
            }

            let size = Int(data[offset]) << 24
                | Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8
                | Int(data[offset + 3])
            guard size >= 8, offset + size <= data.count else {
                throw BMFFValidationError.invalidSize(offset)
            }

            let typeData = data[(offset + 4)..<(offset + 8)]
            let type = String(data: typeData, encoding: .ascii) ?? "????"
            boxes.append(BMFFBoxNode(type: type, size: size, offset: offset))
            offset += size
        }

        return boxes
    }

    public func validateInitSegment(_ data: Data) throws {
        let boxes = try parseTopLevelBoxes(data)
        guard boxes.contains(where: { $0.type == "ftyp" }) else {
            throw BMFFValidationError.missingTopLevel("ftyp")
        }
        guard boxes.contains(where: { $0.type == "moov" }) else {
            throw BMFFValidationError.missingTopLevel("moov")
        }
    }

    public func validateMediaFragment(_ data: Data) throws {
        let boxes = try parseTopLevelBoxes(data)
        guard boxes.contains(where: { $0.type == "moof" }) else {
            throw BMFFValidationError.missingTopLevel("moof")
        }
        guard boxes.contains(where: { $0.type == "mdat" }) else {
            throw BMFFValidationError.missingTopLevel("mdat")
        }
    }
}
