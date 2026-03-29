#if os(tvOS)
import Foundation
import Shared

/// Manages the Quick Connect handshake lifecycle for Apple TV.
///
/// Flow:
/// 1. Call `initiate(serverURL:)` → server returns a 4-char code.
/// 2. Display the code to the user.
/// 3. Poll automatically every 5 s via `startPolling()`.
/// 4. When the user approves on another device, `onAuthenticated` is called.
@MainActor
final class QuickConnectViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case awaitingApproval(code: String)
        case error(String)
    }

    @Published private(set) var state: State = .idle

    private let dependencies: ReelFinDependencies
    private var pollTask: Task<Void, Never>?
    private var secret: String?

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies
    }

    deinit {
        pollTask?.cancel()
    }

    /// Initiates a Quick Connect request and begins polling.
    func initiate(serverURL: URL) async {
        pollTask?.cancel()
        secret = nil
        state = .loading

        do {
            let qc = try await dependencies.apiClient.initiateQuickConnect(serverURL: serverURL)
            secret = qc.secret
            state = .awaitingApproval(code: qc.code)
            startPolling()
        } catch {
            state = .error("Quick Connect unavailable. Try username / password.")
        }
    }

    /// Cancels all polling and resets to idle.
    func cancel() {
        pollTask?.cancel()
        pollTask = nil
        secret = nil
        state = .idle
    }

    var onAuthenticated: ((UserSession) -> Void)?

    // MARK: - Private

    private func startPolling() {
        guard let secret else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self, secret] in
            // Poll immediately, then every 5 s
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll(secret: secret)
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 s
            }
        }
    }

    private func poll(secret: String) async {
        guard case .awaitingApproval = state else { return }
        do {
            if let session = try await dependencies.apiClient.pollQuickConnect(secret: secret) {
                pollTask?.cancel()
                pollTask = nil
                state = .idle
                onAuthenticated?(session)
            }
        } catch {
            // Transient network errors are ignored — keep polling.
            // Fatal errors (invalid server URL) should surface.
            if let appError = error as? AppError, case .invalidServerURL = appError {
                state = .error("Server URL missing. Go back and enter the server address first.")
                pollTask?.cancel()
            }
        }
    }
}
#endif
