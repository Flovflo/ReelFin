import Foundation
import Shared

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var serverURLText = ""
    @Published var username = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var isTestingConnection = false
    @Published var infoMessage: String?
    @Published var errorMessage: String?

    private let dependencies: ReelFinDependencies

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
        if let saved = dependencies.settingsStore.serverConfiguration {
            serverURLText = saved.serverURL.absoluteString
        }
        if let session = dependencies.settingsStore.lastSession {
            username = session.username
        }
    }

    func testConnection() async {
        errorMessage = nil
        infoMessage = nil
        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            let url = try normalizedServerURL(from: serverURLText)
            try await dependencies.apiClient.testConnection(serverURL: url)
            infoMessage = "Connection OK"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func login() async -> UserSession? {
        errorMessage = nil
        infoMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let url = try normalizedServerURL(from: serverURLText)
            let config = ServerConfiguration(
                serverURL: url,
                allowCellularStreaming: dependencies.settingsStore.serverConfiguration?.allowCellularStreaming ?? true,
                preferredQuality: dependencies.settingsStore.serverConfiguration?.preferredQuality ?? .auto,
                playbackStrategy: dependencies.settingsStore.serverConfiguration?.playbackStrategy ?? .bestQualityFastest
            )
            try await dependencies.apiClient.configure(server: config)

            let credentials = UserCredentials(username: username, password: password)
            let session = try await dependencies.apiClient.authenticate(credentials: credentials)
            dependencies.settingsStore.serverConfiguration = config
            dependencies.settingsStore.lastSession = session
            infoMessage = "Welcome, \(session.username)"
            return session
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func normalizedServerURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.invalidServerURL
        }

        let prefixed = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: prefixed), url.host != nil else {
            throw AppError.invalidServerURL
        }

        return url
    }
}
