import Foundation

public struct MatroskaCueParser: Sendable {
    private let reader = EBMLReader()

    public init() {}

    public func parseCues(data: Data) throws -> [MatroskaCuePoint] {
        var cues: [MatroskaCuePoint] = []
        var offset = 0
        while offset < data.count {
            let header = try reader.readHeader(data: data, offset: offset)
            let range = try reader.payloadRange(
                for: header,
                elementOffset: offset,
                parentEnd: data.count,
                dataCount: data.count
            )
            if header.id == EBMLElementID.cuePoint {
                cues.append(try parseCuePoint(data: data, payloadRange: range))
            }
            offset = range.upperBound
        }
        return cues
    }

    private func parseCuePoint(data: Data, payloadRange: Range<Int>) throws -> MatroskaCuePoint {
        var cue = MatroskaCuePoint(timecode: 0)
        var offset = payloadRange.lowerBound
        while offset < payloadRange.upperBound {
            let child = try reader.readHeader(data: data, offset: offset)
            let childRange = try reader.payloadRange(
                for: child,
                elementOffset: offset,
                parentEnd: payloadRange.upperBound,
                dataCount: data.count
            )
            if child.id == EBMLElementID.cueTime {
                cue.timecode = try reader.readUInt(
                    data: data,
                    offset: childRange.lowerBound,
                    size: childRange.count
                )
            } else if child.id == EBMLElementID.cueTrackPositions {
                let position = try parseTrackPosition(data: data, payloadRange: childRange)
                cue.track = position.track
                cue.clusterPosition = position.clusterPosition
            }
            offset = childRange.upperBound
        }
        return cue
    }

    private func parseTrackPosition(
        data: Data,
        payloadRange: Range<Int>
    ) throws -> (track: UInt64?, clusterPosition: UInt64?) {
        var track: UInt64?
        var clusterPosition: UInt64?
        var offset = payloadRange.lowerBound
        while offset < payloadRange.upperBound {
            let child = try reader.readHeader(data: data, offset: offset)
            let childRange = try reader.payloadRange(
                for: child,
                elementOffset: offset,
                parentEnd: payloadRange.upperBound,
                dataCount: data.count
            )
            if child.id == EBMLElementID.cueTrack {
                track = try reader.readUInt(data: data, offset: childRange.lowerBound, size: childRange.count)
            } else if child.id == EBMLElementID.cueClusterPosition {
                clusterPosition = try reader.readUInt(
                    data: data,
                    offset: childRange.lowerBound,
                    size: childRange.count
                )
            }
            offset = childRange.upperBound
        }
        return (track, clusterPosition)
    }
}
