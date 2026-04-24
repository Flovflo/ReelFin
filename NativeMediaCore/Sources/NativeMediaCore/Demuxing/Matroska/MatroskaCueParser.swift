import Foundation

public struct MatroskaCueParser: Sendable {
    private let reader = EBMLReader()

    public init() {}

    public func parseCues(data: Data) throws -> [MatroskaCuePoint] {
        var cues: [MatroskaCuePoint] = []
        var offset = 0
        while offset < data.count {
            let header = try reader.readHeader(data: data, offset: offset)
            if header.id == EBMLElementID.cuePoint {
                cues.append(try parseCuePoint(data: data, header: header))
            }
            offset = payloadEnd(header)
        }
        return cues
    }

    private func parseCuePoint(data: Data, header: EBMLElementHeader) throws -> MatroskaCuePoint {
        var cue = MatroskaCuePoint(timecode: 0)
        var offset = header.payloadOffset
        while offset < payloadEnd(header) {
            let child = try reader.readHeader(data: data, offset: offset)
            if child.id == EBMLElementID.cueTime {
                cue.timecode = try reader.readUInt(data: data, offset: child.payloadOffset, size: Int(child.size ?? 0))
            } else if child.id == EBMLElementID.cueTrackPositions {
                let position = try parseTrackPosition(data: data, header: child)
                cue.track = position.track
                cue.clusterPosition = position.clusterPosition
            }
            offset = payloadEnd(child)
        }
        return cue
    }

    private func parseTrackPosition(data: Data, header: EBMLElementHeader) throws -> (track: UInt64?, clusterPosition: UInt64?) {
        var track: UInt64?
        var clusterPosition: UInt64?
        var offset = header.payloadOffset
        while offset < payloadEnd(header) {
            let child = try reader.readHeader(data: data, offset: offset)
            if child.id == EBMLElementID.cueTrack {
                track = try reader.readUInt(data: data, offset: child.payloadOffset, size: Int(child.size ?? 0))
            } else if child.id == EBMLElementID.cueClusterPosition {
                clusterPosition = try reader.readUInt(data: data, offset: child.payloadOffset, size: Int(child.size ?? 0))
            }
            offset = payloadEnd(child)
        }
        return (track, clusterPosition)
    }

    private func payloadEnd(_ header: EBMLElementHeader) -> Int {
        header.payloadOffset + Int(header.size ?? 0)
    }
}
