import PlaybackEngine
import UIKit

#if os(iOS)
final class PlaybackSkipOverlayView: UIView {
    private let skipButton = UIButton(type: .system)
    private var onSkipSuggestion: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        setupButton()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        suggestion: PlaybackSkipSuggestion?,
        onSkipSuggestion: (() -> Void)?
    ) {
        self.onSkipSuggestion = onSkipSuggestion

        guard let suggestion else {
            skipButton.isHidden = true
            accessibilityElementsHidden = true
            return
        }

        skipButton.isHidden = false
        accessibilityElementsHidden = false
        skipButton.configuration?.title = suggestion.title
        skipButton.accessibilityLabel = suggestion.title
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !skipButton.isHidden else { return false }
        let buttonFrame = skipButton.convert(skipButton.bounds, to: self)
        return buttonFrame.contains(point)
    }

    private func setupButton() {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .white
        configuration.baseForegroundColor = .black
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .headline).withTraits(.traitBold)
            return outgoing
        }
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24)

        skipButton.configuration = configuration
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.isHidden = true
        skipButton.accessibilityHint = "Skips the active intro, recap, credits, or jumps to the next episode."
        skipButton.accessibilityIdentifier = "playback_skip_button"
        skipButton.addTarget(self, action: #selector(handleSkipTap), for: .touchUpInside)
        skipButton.layer.shadowColor = UIColor.black.cgColor
        skipButton.layer.shadowOpacity = 0.24
        skipButton.layer.shadowRadius = 18
        skipButton.layer.shadowOffset = CGSize(width: 0, height: 12)

        addSubview(skipButton)
        NSLayoutConstraint.activate([
            skipButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -24),
            skipButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -28)
        ])
    }

    @objc
    private func handleSkipTap() {
        onSkipSuggestion?()
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
