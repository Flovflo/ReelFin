import Foundation

public final class DefaultSettingsStore: SettingsStoreProtocol {
    private enum Keys {
        static let serverConfiguration = "settings.serverConfiguration"
        static let lastSession = "settings.lastSession"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var serverConfiguration: ServerConfiguration? {
        get { decode(ServerConfiguration.self, key: Keys.serverConfiguration) }
        set { encode(newValue, key: Keys.serverConfiguration) }
    }

    public var lastSession: UserSession? {
        get { decode(UserSession.self, key: Keys.lastSession) }
        set { encode(newValue, key: Keys.lastSession) }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, key: String) {
        if let value, let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
