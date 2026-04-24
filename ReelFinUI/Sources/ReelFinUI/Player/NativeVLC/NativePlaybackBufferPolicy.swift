import Foundation

struct NativePlaybackBufferSnapshot: Equatable {
    var startTime: Double
    var currentVideoPTS: Double
    var currentAudioPTS: Double
    var playbackTime: Double
    var videoQueuedSeconds: Double
    var audioQueuedSeconds: Double
    var videoPacketCount: Int
    var audioPacketCount: Int
    var videoPrimedPacketCount: Int
    var audioPrimedPacketCount: Int

    init(
        startTime: Double,
        currentVideoPTS: Double,
        currentAudioPTS: Double,
        playbackTime: Double,
        videoQueuedSeconds: Double,
        audioQueuedSeconds: Double,
        videoPacketCount: Int,
        audioPacketCount: Int,
        videoPrimedPacketCount: Int,
        audioPrimedPacketCount: Int
    ) {
        self.startTime = startTime
        self.currentVideoPTS = currentVideoPTS
        self.currentAudioPTS = currentAudioPTS
        self.playbackTime = playbackTime
        self.videoQueuedSeconds = videoQueuedSeconds
        self.audioQueuedSeconds = audioQueuedSeconds
        self.videoPacketCount = videoPacketCount
        self.audioPacketCount = audioPacketCount
        self.videoPrimedPacketCount = videoPrimedPacketCount
        self.audioPrimedPacketCount = audioPrimedPacketCount
    }
}

struct NativePlaybackBufferDecision: Equatable {
    var canStart: Bool
    var videoAheadSeconds: Double
    var audioAheadSeconds: Double
    var requiredVideoAheadSeconds: Double
    var requiredAudioAheadSeconds: Double
    var requiredAudioPrimedPacketCount: Int
}

struct NativePlaybackBufferPolicy: Equatable {
    var fastStartVideoAheadSeconds: Double
    var fastStartAudioAheadSeconds: Double
    var fastStartAudioPrimedPacketCount: Int
    var initialVideoAheadSeconds: Double
    var initialAudioAheadSeconds: Double
    var rebufferVideoAheadSeconds: Double
    var rebufferAudioAheadSeconds: Double
    var audioStarvationAheadSeconds: Double
    var initialAudioPrimedPacketCount: Int
    var rebufferAudioPrimedPacketCount: Int
    var maximumAudioStartupWaitSeconds: Double

    static let matroska = NativePlaybackBufferPolicy(
        fastStartVideoAheadSeconds: 1.25,
        fastStartAudioAheadSeconds: 1.25,
        fastStartAudioPrimedPacketCount: 8,
        initialVideoAheadSeconds: 5.0,
        initialAudioAheadSeconds: 8.0,
        rebufferVideoAheadSeconds: 4.0,
        rebufferAudioAheadSeconds: 6.0,
        audioStarvationAheadSeconds: 0.05,
        initialAudioPrimedPacketCount: 32,
        rebufferAudioPrimedPacketCount: 32,
        maximumAudioStartupWaitSeconds: 4.0
    )

    func decision(
        snapshot: NativePlaybackBufferSnapshot,
        needsAudio: Bool,
        isRebuffering: Bool
    ) -> NativePlaybackBufferDecision {
        let referenceTime = max(snapshot.startTime, snapshot.playbackTime)
        let videoAhead = ahead(
            pts: snapshot.currentVideoPTS,
            queuedSeconds: snapshot.videoQueuedSeconds,
            referenceTime: referenceTime
        )
        let audioAhead = ahead(
            pts: snapshot.currentAudioPTS,
            queuedSeconds: snapshot.audioQueuedSeconds,
            referenceTime: referenceTime
        )
        let requiredVideo = isRebuffering ? rebufferVideoAheadSeconds : initialVideoAheadSeconds
        let requiredAudio = isRebuffering ? rebufferAudioAheadSeconds : initialAudioAheadSeconds
        let requiredAudioPrimedPackets = isRebuffering ? rebufferAudioPrimedPacketCount : initialAudioPrimedPacketCount
        let videoRendererPrimed = snapshot.videoPacketCount > 0
        let audioRendererPrimed = !needsAudio || snapshot.audioPrimedPacketCount >= requiredAudioPrimedPackets
        let hasEnoughVideo = videoRendererPrimed && videoAhead >= requiredVideo
        let hasEnoughAudio = !needsAudio || (audioRendererPrimed && audioAhead >= requiredAudio)
        let fastStartReady = !isRebuffering
            && videoRendererPrimed
            && videoAhead >= fastStartVideoAheadSeconds
            && (!needsAudio || (
                snapshot.audioPrimedPacketCount >= fastStartAudioPrimedPacketCount
                && audioAhead >= fastStartAudioAheadSeconds
            ))
        return NativePlaybackBufferDecision(
            canStart: fastStartReady || (hasEnoughVideo && hasEnoughAudio),
            videoAheadSeconds: videoAhead,
            audioAheadSeconds: audioAhead,
            requiredVideoAheadSeconds: isRebuffering ? requiredVideo : fastStartVideoAheadSeconds,
            requiredAudioAheadSeconds: needsAudio ? (isRebuffering ? requiredAudio : fastStartAudioAheadSeconds) : 0,
            requiredAudioPrimedPacketCount: needsAudio ? (isRebuffering ? requiredAudioPrimedPackets : fastStartAudioPrimedPacketCount) : 0
        )
    }

    func shouldRebufferAudio(
        snapshot: NativePlaybackBufferSnapshot,
        needsAudio: Bool,
        isPlaying: Bool
    ) -> Bool {
        guard needsAudio, isPlaying else { return false }
        let audioAhead = ahead(
            pts: snapshot.currentAudioPTS,
            queuedSeconds: snapshot.audioQueuedSeconds,
            referenceTime: snapshot.playbackTime
        )
        return audioAhead < audioStarvationAheadSeconds
    }

    private func ahead(pts: Double, queuedSeconds: Double, referenceTime: Double) -> Double {
        max(0, pts - referenceTime) + max(0, queuedSeconds)
    }
}
