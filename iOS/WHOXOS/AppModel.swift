import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum ConnectionState {
        case unpaired
        case pairing
        case connected
        case disconnected
    }

    enum AuthenticationState: Equatable {
        case checking
        case signedOut
        case signedIn(AuthenticatedUser)
    }

    var connection: ConnectionState = .unpaired
    var authenticationState: AuthenticationState = .checking
    var isAuthenticating = false
    var authenticationError: String?
    var selectedChannel = "Home"
    var draft = ""
    var messages: [ChatMessage] = []

    private let authenticationService = AuthenticationService()

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
            if let authenticationError = error as? AuthenticationError,
               authenticationError != .sessionExpired {
                self.authenticationError = authenticationError.localizedDescription
            }
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
        connection = .unpaired
        authenticationError = nil
        authenticationState = .signedOut
    }

    func sendDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(.init(role: .user, text: trimmed))
        draft = ""
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}
