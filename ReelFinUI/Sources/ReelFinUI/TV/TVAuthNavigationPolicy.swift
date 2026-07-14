#if os(tvOS)
enum TVOnboardingAdvanceResult: Equatable { case advanced, completed }

struct TVOnboardingDeckState: Equatable {
    private(set) var index: Int
    let count: Int

    init(initialIndex: Int?, count: Int) {
        self.count = max(count, 1)
        index = min(max(initialIndex ?? 0, 0), self.count - 1)
    }

    var isFirstPage: Bool { index == 0 }
    var isLastPage: Bool { index == count - 1 }

    mutating func advance() -> TVOnboardingAdvanceResult {
        guard !isLastPage else { return .completed }
        index += 1
        return .advanced
    }

    mutating func retreat() -> Bool {
        guard !isFirstPage else { return false }
        index -= 1
        return true
    }
}

enum TVLoginNavigationPolicy {
    static func preferredFocus(for phase: TVLoginPhase) -> TVLoginFocus? {
        switch phase {
        case .landing: .landingQuickConnect
        case .server: .serverAddress
        case .credentials: .credentialsUsername
        case .quickConnect: .quickConnectUsePassword
        case .submitting, .success: nil
        }
    }

    static func backDestination(
        from phase: TVLoginPhase,
        quickConnectOrigin: TVLoginPhase
    ) -> TVLoginPhase? {
        switch phase {
        case .landing, .submitting, .success:
            nil
        case .server:
            .landing
        case .credentials:
            .server
        case .quickConnect:
            switch quickConnectOrigin {
            case .landing, .server, .credentials:
                quickConnectOrigin
            case .quickConnect, .submitting, .success:
                .landing
            }
        }
    }
}
#endif
