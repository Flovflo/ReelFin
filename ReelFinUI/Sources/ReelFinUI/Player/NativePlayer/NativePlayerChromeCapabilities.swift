import Shared

enum NativePlayerIOSTopAction: CaseIterable, Equatable {
    case pictureInPicture
    case airPlay
    case share
}

enum NativePlayerIOSBottomAction: CaseIterable, Equatable {
    case videoInformation
    case audio
    case subtitles
}

struct NativePlayerChromeCapabilities: Equatable {
    let supportsPictureInPicture: Bool
    let supportsAirPlay: Bool
    let supportsSystemVolume: Bool
    let supportsShare: Bool
    let supportsVideoInformation: Bool
    let hasAudioChoices: Bool
    let hasSubtitleChoices: Bool

    var iOSTopActions: [NativePlayerIOSTopAction] {
        var actions: [NativePlayerIOSTopAction] = []
        if supportsPictureInPicture { actions.append(.pictureInPicture) }
        if supportsAirPlay { actions.append(.airPlay) }
        if supportsShare { actions.append(.share) }
        return actions
    }

    var iOSBottomActions: [NativePlayerIOSBottomAction] {
        var actions: [NativePlayerIOSBottomAction] = []
        if supportsVideoInformation { actions.append(.videoInformation) }
        if hasAudioChoices { actions.append(.audio) }
        if hasSubtitleChoices { actions.append(.subtitles) }
        return actions
    }

    static func nativeSampleBuffer(controls: PlaybackControlsModel) -> Self {
        Self(
            supportsPictureInPicture: false,
            supportsAirPlay: true,
            supportsSystemVolume: true,
            supportsShare: false,
            supportsVideoInformation: true,
            hasAudioChoices: controls.audioOptions.count > 1,
            hasSubtitleChoices: controls.subtitleOptions.contains { $0.trackID != nil }
        )
    }

    static func customAVPlayer(controls: PlaybackControlsModel) -> Self {
        Self(
            supportsPictureInPicture: false,
            supportsAirPlay: true,
            supportsSystemVolume: true,
            supportsShare: false,
            supportsVideoInformation: true,
            hasAudioChoices: controls.audioOptions.count > 1,
            hasSubtitleChoices: controls.subtitleOptions.contains { $0.trackID != nil }
        )
    }
}
