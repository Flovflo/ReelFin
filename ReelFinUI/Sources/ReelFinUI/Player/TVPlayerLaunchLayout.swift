import CoreGraphics

struct TVPlayerLaunchLayout: Equatable, Sendable {
    let maxWidth: CGFloat
    let cornerRadius: CGFloat
    let spinnerSize: CGFloat
    let progressWidth: CGFloat
    let screenInset: CGFloat

    static let standard = TVPlayerLaunchLayout(
        maxWidth: 420,
        cornerRadius: 24,
        spinnerSize: 34,
        progressWidth: 280,
        screenInset: 64
    )
}
