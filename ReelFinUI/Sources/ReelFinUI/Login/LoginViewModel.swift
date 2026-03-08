import Foundation
import Shared

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var serverURLText = ""
    @Published var username = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var isTestingConnection = false
    @Published var serverMessage: String?
    @Published var serverErrorMessage: String?
    @Published var authErrorMessage: String?
    @Published private(set) var validatedServerURL: URL?

    private let dependencies: ReelFinDependencies

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
        if let saved = dependencies.settingsStore.serverConfiguration {
            serverURLText = saved.serverURL.absoluteString
            validatedServerURL = saved.serverURL
        }
        if let session = dependencies.settingsStore.lastSession {
            username = session.username
        }
    }

    var hasSavedServer: Bool {
        !serverURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canAdvanceFromServer: Bool {
        !serverURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTestingConnection
    }

    var canSubmitCredentials: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !isLoading
    }

    func testConnection() async -> Bool {
        serverErrorMessage = nil
        authErrorMessage = nil
        serverMessage = nil
        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            let url = try normalizedServerURL(from: serverURLText)
            try await dependencies.apiClient.testConnection(serverURL: url)
            validatedServerURL = url
            serverMessage = "Server ready"
            return true
        } catch {
            validatedServerURL = nil
            serverErrorMessage = error.localizedDescription
            return false
        }
    }

    func login() async -> UserSession? {
        serverErrorMessage = nil
        authErrorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let url = try validatedServerURL ?? normalizedServerURL(from: serverURLText)
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
            validatedServerURL = url
            return session
        } catch {
            authErrorMessage = error.localizedDescription
            return nil
        }
    }

    func serverURLDidChange() {
        serverMessage = nil
        serverErrorMessage = nil

        guard let validatedServerURL else {
            return
        }

        let currentValue = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentValue != validatedServerURL.absoluteString {
            self.validatedServerURL = nil
        }
    }

    func clearAuthError() {
        authErrorMessage = nil
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
