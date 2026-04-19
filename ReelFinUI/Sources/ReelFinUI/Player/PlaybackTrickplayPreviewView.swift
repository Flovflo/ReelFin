import Shared
import UIKit

#if os(iOS)
final class PlaybackTrickplayPreviewView: UIView {
    private struct PreviewKey: Equatable {
        let width: Int
        let tileImageIndex: Int
        let thumbnailIndex: Int
    }

    private struct SheetKey: Equatable {
        let width: Int
        let tileImageIndex: Int
    }

    private let materialView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let imageView = UIImageView()
    private let timeLabel = UILabel()
    private let consumerID = ImageRequestConsumerID()
    private let previewWidth: CGFloat = 220

    private var manifest: TrickplayManifest?
    private var timeOffsetSeconds: Double = 0
    private var apiClient: JellyfinAPIClientProtocol?
    private var imagePipeline: ImagePipelineProtocol?
    private var previewKey: PreviewKey?
    private var loadedSheetKey: SheetKey?
    private var loadedSheetImage: UIImage?
    private var activeSheetURL: URL?
    private var tileBaseURLsByWidth: [Int: URL] = [:]
    private var loadTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var allowPreviewWhilePlayingUntil: Date?
    private var lastObservedSeconds: Double?
    private var aspectRatio: CGFloat = 9 / 16
    private var imageAspectConstraint: NSLayoutConstraint?

    override var intrinsicContentSize: CGSize {
        CGSize(width: previewWidth, height: (previewWidth * aspectRatio) + 34)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        alpha = 0
        isHidden = true
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        hideTask?.cancel()
        if let activeSheetURL {
            imagePipeline?.cancel(url: activeSheetURL, consumer: consumerID)
        }
    }

    func update(
        manifest: TrickplayManifest?,
        timeOffsetSeconds: Double,
        apiClient: JellyfinAPIClientProtocol,
        imagePipeline: ImagePipelineProtocol
    ) {
        let didChangeManifest = self.manifest != manifest
        self.manifest = manifest
        self.timeOffsetSeconds = timeOffsetSeconds
        self.apiClient = apiClient
        self.imagePipeline = imagePipeline

        if didChangeManifest {
            loadTask?.cancel()
            if let activeSheetURL {
                imagePipeline.cancel(url: activeSheetURL, consumer: consumerID)
            }
            activeSheetURL = nil
            allowPreviewWhilePlayingUntil = nil
            lastObservedSeconds = nil
            tileBaseURLsByWidth.removeAll()
            previewKey = nil
            loadedSheetKey = nil
            loadedSheetImage = nil
            imageView.image = nil
        }

        if let variant = manifest?.preferredVariant(forThumbnailWidth: Int(previewWidth.rounded())) {
            updateAspectRatio(CGFloat(variant.height) / CGFloat(variant.width))
        } else {
            updateAspectRatio(9 / 16)
            hideImmediately()
        }
    }

    func handleTimeJump(seconds: Double, isPlaying: Bool, durationSeconds: Double) {
        allowPreviewWhilePlayingUntil = Date().addingTimeInterval(0.8)
        handleObservedTimeChange(seconds: seconds, isPlaying: isPlaying, durationSeconds: durationSeconds)
    }

    func handleObservedTimeChange(seconds: Double, isPlaying: Bool, durationSeconds: Double) {
        if let lastObservedSeconds, isPlaying, abs(seconds - lastObservedSeconds) > 0.75 {
            allowPreviewWhilePlayingUntil = Date().addingTimeInterval(0.8)
        }
        lastObservedSeconds = seconds

        updateHorizontalPosition(seconds: seconds, durationSeconds: durationSeconds)

        let allowWhilePlaying = allowPreviewWhilePlayingUntil?.timeIntervalSinceNow ?? 0 > 0
        guard
            (!isPlaying || allowWhilePlaying),
            let manifest,
            let variant = manifest.preferredVariant(forThumbnailWidth: Int(previewWidth.rounded())),
            let frame = variant.frame(for: seconds + timeOffsetSeconds)
        else {
            hideAnimated()
            return
        }

        let key = PreviewKey(width: variant.width, tileImageIndex: frame.tileImageIndex, thumbnailIndex: frame.thumbnailIndex)
        timeLabel.text = Self.format(seconds: max(0, seconds + timeOffsetSeconds))

        showIfNeeded()
        scheduleHide()

        guard key != previewKey else { return }
        previewKey = key
        loadPreviewImage(frame: frame, variant: variant)
    }

    private func setupView() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 24
        layer.shadowOffset = CGSize(width: 0, height: 16)

        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.clipsToBounds = true
        materialView.layer.cornerCurve = .continuous
        materialView.layer.cornerRadius = 20

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.04)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center

        addSubview(materialView)
        materialView.contentView.addSubview(imageView)
        materialView.contentView.addSubview(timeLabel)

        let imageAspectConstraint = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: aspectRatio)
        self.imageAspectConstraint = imageAspectConstraint

        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: trailingAnchor),
            materialView.topAnchor.constraint(equalTo: topAnchor),
            materialView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: materialView.contentView.leadingAnchor, constant: 10),
            imageView.trailingAnchor.constraint(equalTo: materialView.contentView.trailingAnchor, constant: -10),
            imageView.topAnchor.constraint(equalTo: materialView.contentView.topAnchor, constant: 10),
            timeLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            timeLabel.leadingAnchor.constraint(equalTo: materialView.contentView.leadingAnchor, constant: 10),
            timeLabel.trailingAnchor.constraint(equalTo: materialView.contentView.trailingAnchor, constant: -10),
            timeLabel.bottomAnchor.constraint(equalTo: materialView.contentView.bottomAnchor, constant: -10),
            imageAspectConstraint
        ])
    }

    private func loadPreviewImage(frame: TrickplayFrame, variant: TrickplayVariant) {
        if let loadedSheetKey, let loadedSheetImage, loadedSheetKey == SheetKey(width: variant.width, tileImageIndex: frame.tileImageIndex) {
            imageView.image = loadedSheetImage.reelfinCropped(to: frame.cropRect)
            return
        }

        imageView.image = nil
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            guard
                let imageURL = await self.imageURL(for: variant, tileImageIndex: frame.tileImageIndex),
                let imagePipeline = self.imagePipeline
            else {
                return
            }

            if let activeSheetURL, activeSheetURL != imageURL {
                imagePipeline.cancel(url: activeSheetURL, consumer: consumerID)
            }
            activeSheetURL = imageURL

            guard let sheetImage = try? await imagePipeline.image(for: imageURL, consumer: consumerID) else { return }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                let expectedKey = SheetKey(width: variant.width, tileImageIndex: frame.tileImageIndex)
                guard self.previewKey?.thumbnailIndex == frame.thumbnailIndex else { return }
                self.loadedSheetKey = expectedKey
                self.loadedSheetImage = sheetImage
                self.imageView.image = sheetImage.reelfinCropped(to: frame.cropRect)
            }
        }
    }

    private func imageURL(for variant: TrickplayVariant, tileImageIndex: Int) async -> URL? {
        if let cachedBaseURL = tileBaseURLsByWidth[variant.width] {
            return Self.tileImageURL(baseURL: cachedBaseURL, tileImageIndex: tileImageIndex)
        }

        guard
            let manifest,
            let apiClient,
            let baseURL = await apiClient.trickplayTileBaseURL(
                itemID: manifest.itemID,
                mediaSourceID: manifest.sourceID,
                width: variant.width
            )
        else {
            return nil
        }

        tileBaseURLsByWidth[variant.width] = baseURL
        return Self.tileImageURL(baseURL: baseURL, tileImageIndex: tileImageIndex)
    }

    private func showIfNeeded() {
        guard isHidden || alpha < 1 else { return }
        hideTask?.cancel()
        isHidden = false
        UIView.animate(withDuration: 0.16) {
            self.alpha = 1
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.hideAnimated()
            }
        }
    }

    private func hideAnimated() {
        guard !isHidden else { return }
        UIView.animate(withDuration: 0.18) {
            self.alpha = 0
        } completion: { _ in
            self.isHidden = true
        }
    }

    private func hideImmediately() {
        hideTask?.cancel()
        allowPreviewWhilePlayingUntil = nil
        alpha = 0
        isHidden = true
    }

    private func updateHorizontalPosition(seconds: Double, durationSeconds: Double) {
        guard let container = superview else {
            transform = .identity
            return
        }

        let effectiveDuration = max(0.001, durationSeconds + timeOffsetSeconds)
        let progress = min(max((seconds + timeOffsetSeconds) / effectiveDuration, 0), 1)
        let previewHalfWidth = max(bounds.width, intrinsicContentSize.width) / 2
        let leftInset = max(container.safeAreaInsets.left + previewHalfWidth + 18, previewHalfWidth + 18)
        let rightInset = max(container.safeAreaInsets.right + previewHalfWidth + 18, previewHalfWidth + 18)
        let usableWidth = max(0, container.bounds.width - leftInset - rightInset)
        let targetCenterX = leftInset + (usableWidth * progress)
        let containerCenterX = container.bounds.midX

        transform = CGAffineTransform(translationX: targetCenterX - containerCenterX, y: 0)
    }

    private func updateAspectRatio(_ newValue: CGFloat) {
        guard abs(aspectRatio - newValue) > 0.001 else { return }
        aspectRatio = newValue
        if let imageAspectConstraint {
            NSLayoutConstraint.deactivate([imageAspectConstraint])
        }
        let replacement = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: aspectRatio)
        self.imageAspectConstraint = replacement
        NSLayoutConstraint.activate([replacement])
        invalidateIntrinsicContentSize()
    }

    private static func tileImageURL(baseURL: URL, tileImageIndex: Int) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path += "/\(tileImageIndex).jpg"
        return components.url
    }

    private static func format(seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

private extension UIImage {
    func reelfinCropped(to rect: CGRect) -> UIImage {
        let scaledRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        ).integral

        guard let cgImage, let cropped = cgImage.cropping(to: scaledRect) else {
            return self
        }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}
#endif
