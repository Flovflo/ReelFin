import NativeMediaCore
import UIKit

final class NativeSubtitleOverlayView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 30, weight: .semibold)
        label.textColor = .white
        label.shadowColor = .black
        label.shadowOffset = CGSize(width: 0, height: 2)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.65
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 36),
            label.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -36),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -54)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(cues: [SubtitleCue]) {
        let text = cues.map(\.text).joined(separator: "\n")
        label.text = text
        label.isHidden = text.isEmpty
    }
}
