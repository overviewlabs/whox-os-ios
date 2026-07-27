import Foundation
import Observation
import WHOXCore

@MainActor
@Observable
final class AppModel {
    enum Connection: Equatable {
        case unpaired
        case connecting
        case connected(serverName: String)
        case failed(message: String)
    }

    enum AuthenticationState: Equatable {
        case checking
        case signedOut
        case signedIn(AuthenticatedUser)
    }

    var connection: Connection = .unpaired
    var sessions: [WHOXSession] = []
    var selectedSessionID: String?
    var activeRunID: String?
    var pendingApproval: RunEvent?

    var authenticationState: AuthenticationState = .checking
    var isAuthenticating = false
    var authenticationError: String?

    private let authenticationService = AuthenticationService()

    var selectedSession: WHOXSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    var authenticatedUser: AuthenticatedUser? {
        guard case let .signedIn(user) = authenticationState else { return nil }
        return user
    }

    func restoreAuthenticationIfNeeded() async {
        guard authenticationState == .checking else { return }

        do {
            if let session = try await authenticationService.restoreSession() {
                authenticationState = .signedIn(session.user)
            } else {
                authenticationState = .signedOut
            }
        } catch {
            authenticationState = .signedOut
            authenticationError = nil
        }
    }

    func signIn(email: String, password: String) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authenticationError = nil
        defer { isAuthenticating = false }

        do {
            let session = try await authenticationService.signIn(email: email, password: password)
            authenticationState = .signedIn(session.user)
        } catch {
            authenticationError = (error as? LocalizedError)?.errorDescription
                ?? AuthenticationError.unavailable.localizedDescription
        }
    }

    func signOut() async {
        await authenticationService.signOut()
        authenticationState = .signedOut
        authenticationError = nil
        connection = .unpaired
    }

    func pair(with code: String) async {
        guard connection != .connecting else { return }
        connection = .connecting
        try? await Task.sleep(for: .milliseconds(500))
        connection = code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .failed(message: "Enter a pairing code.")
            : .connected(serverName: "WHOX Relay")
    }

    func disconnect() async {
        connection = .unpaired
    }
}
