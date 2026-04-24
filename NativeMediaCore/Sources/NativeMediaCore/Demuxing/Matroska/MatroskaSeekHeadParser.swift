import Foundation

public struct MatroskaSeekHeadParser: Sendable {
    public init() {}

    public func parse(data: Data) -> [UInt32: UInt64] {
        _ = data
        return [:]
    }
}
