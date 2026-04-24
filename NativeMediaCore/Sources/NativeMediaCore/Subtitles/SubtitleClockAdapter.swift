import CoreMedia
import Foundation

public struct SubtitleClockAdapter: Sendable {
    public var delay: CMTime

    public init(delay: CMTime = .zero) {
        self.delay = delay
    }

    public func activeCues(from cues: [SubtitleCue], at playbackTime: CMTime) -> [SubtitleCue] {
        let adjusted = playbackTime - delay
        return cues.filter { cue in
            cue.start <= adjusted && adjusted < cue.end
        }
    }
}
