import Foundation

public enum ColorSpaceMapper {
    public static func hdrFormat(metadata: HDRMetadata?) -> HDRFormat {
        metadata?.format ?? .unknown
    }
}

public struct HDRRenderMetadata: Codable, Hashable, Sendable {
    public var metadata: HDRMetadata
    public var outputMode: HDRFormat
    public var preserved: Bool

    public init(metadata: HDRMetadata, outputMode: HDRFormat, preserved: Bool) {
        self.metadata = metadata
        self.outputMode = outputMode
        self.preserved = preserved
    }
}
