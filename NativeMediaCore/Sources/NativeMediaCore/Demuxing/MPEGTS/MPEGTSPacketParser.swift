import Foundation

struct MPEGTSPacketParser: Sendable {
    let packetSize: Int
    let syncOffset: Int

    init(format: ContainerFormat) {
        switch format {
        case .m2ts:
            packetSize = 192
            syncOffset = 4
        default:
            packetSize = 188
            syncOffset = 0
        }
    }

    func parse(data: Data, absoluteOffset: Int64) throws -> MPEGTSPacket {
        guard data.count == packetSize else { throw MPEGTransportStreamError.invalidPacketSize(data.count) }
        guard data[data.index(data.startIndex, offsetBy: syncOffset)] == 0x47 else {
            throw MPEGTransportStreamError.syncByteMissing(offset: absoluteOffset + Int64(syncOffset))
        }
        let header = data.index(data.startIndex, offsetBy: syncOffset + 1)
        let b1 = data[header]
        let b2 = data[data.index(after: header)]
        let b3 = data[data.index(header, offsetBy: 2)]
        let pid = (Int(b1 & 0x1F) << 8) | Int(b2)
        let payloadUnitStart = (b1 & 0x40) != 0
        let adaptationControl = (b3 & 0x30) >> 4
        let continuityCounter = b3 & 0x0F
        var payloadOffset = syncOffset + 4

        if adaptationControl == 0 || adaptationControl == 2 {
            return MPEGTSPacket(pid: pid, payloadUnitStart: payloadUnitStart, continuityCounter: continuityCounter, payload: Data())
        }
        if adaptationControl == 3 {
            guard payloadOffset < data.count else {
                return MPEGTSPacket(pid: pid, payloadUnitStart: payloadUnitStart, continuityCounter: continuityCounter, payload: Data())
            }
            let length = Int(data[data.index(data.startIndex, offsetBy: payloadOffset)])
            payloadOffset += 1 + length
        }
        guard payloadOffset <= data.count else {
            return MPEGTSPacket(pid: pid, payloadUnitStart: payloadUnitStart, continuityCounter: continuityCounter, payload: Data())
        }
        return MPEGTSPacket(
            pid: pid,
            payloadUnitStart: payloadUnitStart,
            continuityCounter: continuityCounter,
            payload: Data(data[data.index(data.startIndex, offsetBy: payloadOffset)..<data.endIndex])
        )
    }
}
