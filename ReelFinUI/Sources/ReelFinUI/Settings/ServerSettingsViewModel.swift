import Foundation
import Shared

@MainActor
final class ServerSettingsViewModel: ObservableObject {
    @Published var serverURLText = ""
    @Published var username = ""
    @Published var allowCellularStreaming = true
    @Published var preferredQuality: QualityPreference = .auto
    @Published var infoMessage: String?
    @Published var errorMessage: String?

    private let dependencies: ReelFinDependencies

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies

        if let config = dependencies.settingsStore.serverConfiguration {
            serverURLText = config.serverURL.absoluteString
            allowCellularStreaming = config.allowCellularStreaming
            preferredQuality = config.preferredQuality
        }

        if let session = dependencies.settingsStore.lastSession {
            username = session.username
        }
    }

    func save() async {
        errorMessage = nil
        infoMessage = nil

        do {
            guard let url = URL(string: serverURLText), url.host != nil else {
                throw AppError.invalidServerURL
            }

            let config = ServerConfiguration(
                serverURL: url,
                allowCellularStreaming: allowCellularStreaming,
                preferredQuality: preferredQuality
            )
            try await dependencies.apiClient.configure(server: config)
            dependencies.settingsStore.serverConfiguration = config
            infoMessage = "Settings saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func testConnection() async {
        errorMessage = nil
        infoMessage = nil

        do {
            guard let url = URL(string: serverURLText), url.host != nil else {
                throw AppError.invalidServerURL
            }
            try await dependencies.apiClient.testConnection(serverURL: url)
            infoMessage = "Connection OK"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
