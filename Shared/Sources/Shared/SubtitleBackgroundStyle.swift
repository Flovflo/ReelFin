public enum SubtitleBackgroundStyle: String, CaseIterable, Codable, Sendable {
    case transparent
    case subtle

    public static let defaultsKey = "reelfin.subtitle.background-style"

    public var displayName: String {
        switch self {
        case .transparent:
            return "Transparent Background"
        case .subtle:
            return "Subtle Background"
        }
    }
}
