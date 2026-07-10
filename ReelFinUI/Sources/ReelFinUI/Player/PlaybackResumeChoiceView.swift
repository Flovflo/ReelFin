import Foundation
import PlaybackEngine
import Shared
import SwiftUI

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
        }
        .onExitCommand(perform: onCancel)
        .accessibilityIdentifier("playback_resume_choice")
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
        .accessibilityIdentifier(
            choice == .resume ? "playback_resume_choice_continue" : "playback_resume_choice_restart"
        )
    }
}
#endif
