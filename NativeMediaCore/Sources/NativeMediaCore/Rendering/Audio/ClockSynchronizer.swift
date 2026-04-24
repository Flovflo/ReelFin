import CoreMedia
import Foundation

public actor MasterClock {
    private var anchorMediaTime = CMTime.zero
    private var anchorHostTime = Date()
    private var rate: Double = 1

    public init() {}

    public func reset(to time: CMTime = .zero, rate: Double = 1) {
        anchorMediaTime = time
        anchorHostTime = Date()
        self.rate = rate
    }

    public func currentTime() -> CMTime {
        let elapsed = Date().timeIntervalSince(anchorHostTime) * rate
        return anchorMediaTime + CMTime(seconds: elapsed, preferredTimescale: 1000)
    }
}

public actor AudioClock {
    private var time = CMTime.zero

    public init() {}

    public func update(_ newTime: CMTime) {
        time = newTime
    }

    public func currentTime() -> CMTime {
        time
    }
}

public actor VideoClock {
    private var time = CMTime.zero

    public init() {}

    public func update(_ newTime: CMTime) {
        time = newTime
    }

    public func currentTime() -> CMTime {
        time
    }
}

public struct SyncDiagnostics: Equatable, Sendable {
    public var avSyncOffsetMs: Double
    public var driftCorrectionMs: Double

    public init(avSyncOffsetMs: Double = 0, driftCorrectionMs: Double = 0) {
        self.avSyncOffsetMs = avSyncOffsetMs
        self.driftCorrectionMs = driftCorrectionMs
    }
}

public actor ClockSynchronizer {
    private let audioClock: AudioClock
    private let videoClock: VideoClock
    private var snapshot = SyncDiagnostics()

    public init(audioClock: AudioClock = AudioClock(), videoClock: VideoClock = VideoClock()) {
        self.audioClock = audioClock
        self.videoClock = videoClock
    }

    public func update() async {
        let audio = await audioClock.currentTime()
        let video = await videoClock.currentTime()
        snapshot.avSyncOffsetMs = (video.seconds - audio.seconds) * 1000
        snapshot.driftCorrectionMs = DriftCorrector().correctionMilliseconds(offsetMs: snapshot.avSyncOffsetMs)
    }

    public func diagnostics() -> SyncDiagnostics {
        snapshot
    }
}

public struct DriftCorrector: Sendable {
    public init() {}

    public func correctionMilliseconds(offsetMs: Double) -> Double {
        abs(offsetMs) < 20 ? 0 : -offsetMs * 0.1
    }
}
