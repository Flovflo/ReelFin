struct NativePlayerTrackTransitionState: Equatable {
    enum RowStatus: Equatable {
        case idle
        case selected
        case pending
    }

    private(set) var confirmedAudioID: String?
    private(set) var confirmedSubtitleID: String?
    private(set) var pendingSelection: PlaybackControlSelection?
    private(set) var failureMessage: String?

    init(
        confirmedAudioID: String? = nil,
        confirmedSubtitleID: String? = nil
    ) {
        self.confirmedAudioID = confirmedAudioID
        self.confirmedSubtitleID = confirmedSubtitleID
    }

    mutating func request(_ selection: PlaybackControlSelection) {
        pendingSelection = selection
        failureMessage = nil
    }

    mutating func confirm(audioID: String?, subtitleID: String?) {
        confirmedAudioID = audioID
        confirmedSubtitleID = subtitleID

        switch pendingSelection {
        case let .audio(trackID) where trackID == audioID:
            pendingSelection = nil
        case let .subtitle(trackID) where trackID == subtitleID:
            pendingSelection = nil
        default:
            break
        }
    }

    mutating func failPendingRequest() {
        guard pendingSelection != nil else { return }
        pendingSelection = nil
        failureMessage = "Impossible de changer la piste"
    }

    mutating func clearFailure() {
        failureMessage = nil
    }

    func status(for selection: PlaybackControlSelection) -> RowStatus {
        if pendingSelection == selection { return .pending }

        switch selection {
        case let .audio(trackID):
            return trackID == confirmedAudioID ? .selected : .idle
        case let .subtitle(trackID):
            return trackID == confirmedSubtitleID ? .selected : .idle
        }
    }
}

extension NativePlayerTrackTransitionState.RowStatus {
    var accessibilityValue: String {
        switch self {
        case .idle: return "not_selected"
        case .selected: return "selected"
        case .pending: return "pending"
        }
    }
}
