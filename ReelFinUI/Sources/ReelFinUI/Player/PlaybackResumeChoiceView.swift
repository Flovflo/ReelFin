import Foundation
import PlaybackEngine
import Shared
import SwiftUI
#if os(tvOS)
import UIKit
#endif

enum PlaybackLaunchChoice: Hashable, Sendable {
    case resume
    case restart
}

enum PlaybackResumeChoiceExitAction: Equatable, Sendable {
    case cancel
}

struct PlaybackLaunchChoicePolicy {
    static let completionThreshold = 0.97
    static let orderedChoices: [PlaybackLaunchChoice] = [.resume, .restart]
    static let defaultFocusedChoice: PlaybackLaunchChoice = .resume
    static let exitCommandAction: PlaybackResumeChoiceExitAction = .cancel

    static func shouldPresentChoice(
        for item: MediaItem,
        progress: PlaybackProgress? = nil
    ) -> Bool {
        resumePositionTicks(for: item, progress: progress) != nil
    }

    static func resumePositionTicks(
        for item: MediaItem,
        progress: PlaybackProgress? = nil
    ) -> Int64? {
        guard item.mediaType == .movie || item.mediaType == .episode else { return nil }

        let matchingProgress = progress.flatMap { candidate in
            candidate.itemID == item.id && candidate.positionTicks > 0 ? candidate : nil
        }
        let positionTicks: Int64
        let totalTicks: Int64?

        if let matchingProgress {
            positionTicks = matchingProgress.positionTicks
            totalTicks = matchingProgress.totalTicks > 0
                ? matchingProgress.totalTicks
                : item.runtimeTicks
        } else {
            guard !item.isPlayed, let savedPosition = item.playbackPositionTicks, savedPosition > 0 else {
                return nil
            }
            positionTicks = savedPosition
            totalTicks = item.runtimeTicks
        }

        if let totalTicks, totalTicks > 0 {
            let ratio = Double(positionTicks) / Double(totalTicks)
            guard ratio < completionThreshold else { return nil }
        }

        return positionTicks
    }

    static func startPosition(for choice: PlaybackLaunchChoice) -> PlaybackStartPosition {
        switch choice {
        case .resume:
            return .resumeIfAvailable
        case .restart:
            return .beginning
        }
    }

    static func title(for choice: PlaybackLaunchChoice, resumeSeconds: TimeInterval) -> String {
        switch choice {
        case .resume:
            return "Continuer à \(formattedTime(resumeSeconds))"
        case .restart:
            return "Recommencer"
        }
    }

    private static func formattedTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

enum PlaybackLaunchPlayerRoute: CaseIterable {
    case custom
    case legacy
}

struct PlaybackLaunchRequest {
    let item: MediaItem
    let startPosition: PlaybackStartPosition
    let resumePositionTicks: Int64?

    func startPosition(for route: PlaybackLaunchPlayerRoute) -> PlaybackStartPosition {
        _ = route
        return startPosition
    }
}

enum PlaybackLaunchPresentationIntent: Identifiable {
    case chooseStart(item: MediaItem, resumePositionTicks: Int64)

    var id: String { item.id }

    var item: MediaItem {
        switch self {
        case .chooseStart(let item, _):
            return item
        }
    }

    var resumePositionTicks: Int64 {
        switch self {
        case .chooseStart(_, let resumePositionTicks):
            return resumePositionTicks
        }
    }
}

struct PlaybackLaunchCoordinator {
    private(set) var presentationIntent: PlaybackLaunchPresentationIntent?

    mutating func begin(
        item: MediaItem,
        progress: PlaybackProgress?,
        presentsExplicitChoice: Bool
    ) -> PlaybackLaunchRequest? {
        let resumePositionTicks = PlaybackLaunchChoicePolicy.resumePositionTicks(
            for: item,
            progress: progress
        )

        guard let resumePositionTicks else {
            presentationIntent = nil
            return PlaybackLaunchRequest(
                item: item,
                startPosition: .beginning,
                resumePositionTicks: nil
            )
        }

        guard presentsExplicitChoice else {
            presentationIntent = nil
            return PlaybackLaunchRequest(
                item: item,
                startPosition: .resumeIfAvailable,
                resumePositionTicks: resumePositionTicks
            )
        }

        presentationIntent = .chooseStart(
            item: item,
            resumePositionTicks: resumePositionTicks
        )
        return nil
    }

    mutating func resolve(choice: PlaybackLaunchChoice) -> PlaybackLaunchRequest? {
        guard let intent = presentationIntent else { return nil }
        presentationIntent = nil
        return PlaybackLaunchRequest(
            item: intent.item,
            startPosition: PlaybackLaunchChoicePolicy.startPosition(for: choice),
            resumePositionTicks: intent.resumePositionTicks
        )
    }

    mutating func cancel() {
        presentationIntent = nil
    }
}

@MainActor
struct PlaybackLaunchEntryEffects {
    let select: (MediaItem) -> Void
    let prepare: (MediaItem) -> Void
    let launch: (PlaybackLaunchRequest) -> Void
}

@MainActor
struct PlaybackLaunchEntryRouter {
    private var coordinator = PlaybackLaunchCoordinator()

    var presentationIntent: PlaybackLaunchPresentationIntent? {
        coordinator.presentationIntent
    }

    mutating func begin(
        item: MediaItem,
        progress: PlaybackProgress?,
        presentsExplicitChoice: Bool,
        effects: PlaybackLaunchEntryEffects
    ) {
        guard let request = coordinator.begin(
            item: item,
            progress: progress,
            presentsExplicitChoice: presentsExplicitChoice
        ) else { return }
        emit(request, effects: effects)
    }

    mutating func resolve(
        choice: PlaybackLaunchChoice,
        effects: PlaybackLaunchEntryEffects
    ) {
        guard let request = coordinator.resolve(choice: choice) else { return }
        emit(request, effects: effects)
    }

    mutating func cancel() {
        coordinator.cancel()
    }

    private func emit(
        _ request: PlaybackLaunchRequest,
        effects: PlaybackLaunchEntryEffects
    ) {
        effects.select(request.item)
        effects.prepare(request.item)
        effects.launch(request)
    }
}

#if os(tvOS)
struct PlaybackResumeChoiceView: View {
    let itemTitle: String
    let resumePositionTicks: Int64
    let onSelect: (PlaybackStartPosition) -> Void
    let onCancel: () -> Void

    @FocusState private var focusedChoice: PlaybackLaunchChoice?
    @Namespace private var focusScope

    var body: some View {
        ZStack {
            Color.black.opacity(0.76)
                .ignoresSafeArea()

            VStack(spacing: 34) {
                VStack(spacing: 10) {
                    Text(itemTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

                    Text("Comment voulez-vous regarder ?")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }

                GlassEffectContainer(spacing: 22) {
                    HStack(spacing: 22) {
                        choiceButton(.resume, systemImage: "play.fill")
                        choiceButton(.restart, systemImage: "arrow.counterclockwise")
                    }
                }
                .focusScope(focusScope)
                .defaultFocus($focusedChoice, .resume, priority: .userInitiated)
            }
            .padding(.horizontal, 70)
            .padding(.vertical, 58)
            .frame(maxWidth: 1_040)
            .background {
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .glassEffect(.regular, in: .rect(cornerRadius: 42))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 50, y: 24)

            if TVLiveUIAutomationPolicy.isEnabledForCurrentProcess {
                PlaybackResumeChoiceAccessibilityAnchor(focusedChoice: focusedChoice)
                    .frame(width: 1, height: 1)
            }
        }
        .onExitCommand(perform: onCancel)
        .onAppear {
            focusedChoice = PlaybackLaunchChoicePolicy.defaultFocusedChoice
        }
    }

    private func choiceButton(
        _ choice: PlaybackLaunchChoice,
        systemImage: String
    ) -> some View {
        Button {
            onSelect(PlaybackLaunchChoicePolicy.startPosition(for: choice))
        } label: {
            Label(
                PlaybackLaunchChoicePolicy.title(
                    for: choice,
                    resumeSeconds: Double(resumePositionTicks) / 10_000_000
                ),
                systemImage: systemImage
            )
            .font(.title3.weight(.semibold))
            .frame(minWidth: 310, minHeight: 76)
        }
        .buttonStyle(.glass)
        .focused($focusedChoice, equals: choice)
        .prefersDefaultFocus(choice == .resume, in: focusScope)
    }
}

private struct PlaybackResumeChoiceAccessibilityAnchor: UIViewRepresentable {
    let focusedChoice: PlaybackLaunchChoice?

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.isAccessibilityElement = false
        container.isUserInteractionEnabled = false
        for identifier in [
            "playback_resume_choice",
            "playback_resume_choice_continue",
            "playback_resume_choice_restart"
        ] {
            let marker = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            marker.isAccessibilityElement = true
            marker.accessibilityIdentifier = identifier
            marker.accessibilityLabel = identifier
            container.addSubview(marker)
        }
        return container
    }

    func updateUIView(_ view: UIView, context: Context) {
        for marker in view.subviews {
            switch marker.accessibilityIdentifier {
            case "playback_resume_choice":
                marker.accessibilityValue = focusedChoice == .restart ? "restart_focused" : "resume_focused"
            case "playback_resume_choice_continue":
                marker.accessibilityValue = focusedChoice == .resume ? "focused" : "not_focused"
            case "playback_resume_choice_restart":
                marker.accessibilityValue = focusedChoice == .restart ? "focused" : "not_focused"
            default:
                break
            }
        }
    }
}
#endif
