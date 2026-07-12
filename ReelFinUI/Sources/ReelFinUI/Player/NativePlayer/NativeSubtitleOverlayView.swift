import NativeMediaCore
import Shared
import UIKit

final class NativeSubtitleOverlayView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let style = Self.presentationStyle
        isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = style.maximumLineCount
        label.textAlignment = .center
        label.font = .systemFont(ofSize: style.fontSize, weight: .semibold)
        label.textColor = .white
        label.shadowColor = .black
        label.shadowOffset = CGSize(width: 0, height: 2)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.65
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 36),
            label.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -36),
            label.widthAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.widthAnchor, multiplier: style.maximumWidthRatio),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -style.bottomPadding)
        ])
    }

    private static var presentationStyle: CustomPlayerSubtitlePresentationStyle {
#if os(tvOS)
        CustomPlayerSubtitlePresentationPolicy.style(for: .tvOS)
#else
        CustomPlayerSubtitlePresentationPolicy.style(for: .iOS)
#endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(cues: [SubtitleCue]) {
        let rawStyle = UserDefaults.standard.string(
            forKey: SubtitleBackgroundStyle.defaultsKey
        )
        let backgroundStyle = rawStyle.flatMap(SubtitleBackgroundStyle.init(rawValue:))
            ?? .transparent
        let style = Self.presentationStyle
        let backgroundOpacity = CustomPlayerSubtitlePresentationPolicy.backgroundOpacity(
            for: backgroundStyle,
            platform: Self.presentationPlatform
        )
        label.backgroundColor = UIColor.black.withAlphaComponent(backgroundOpacity)
        label.layer.cornerRadius = style.cornerRadius
        label.layer.masksToBounds = backgroundOpacity > 0

        let text = cues.map(\.text).joined(separator: "\n")
        label.text = text
        label.isHidden = text.isEmpty
    }

    private static var presentationPlatform: CustomPlayerSubtitlePlatform {
#if os(tvOS)
        .tvOS
#else
        .iOS
#endif
    }
}
