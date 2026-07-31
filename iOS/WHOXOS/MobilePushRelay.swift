import Foundation
import UIKit

actor MobilePushRelay {
    static let shared = MobilePushRelay()

    private static let baseURL = URL(string: "https://mobile-api.whox.ai")!
    private static let refreshAccount = "mobile-push-refresh-token"
    private static let credentialAccount = "mobile-push-device-credential"
    private static let deviceTokenAccount = "mobile-push-apns-token"
    private static let emailKey = "mobile.push.email"
    private static let installationKey = "mobile.push.installation-id"

    private var accessToken: String?
    private var stateVersion: Int?

    nonisolated static var isProvisioned: Bool {
        KeychainSecret.load(account: credentialAccount) != nil
    }

    nonisolated static var savedEmail: String {
        UserDefaults.standard.string(forKey: emailKey) ?? ""
    }

    func signIn(email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else { throw MobilePushError.missingCredentials }
        let response: AuthResponse = try await request(
            path: "/v1/auth/login",
            method: "POST",
            bearer: nil,
            body: LoginRequest(email: normalizedEmail, password: password, deviceName: UIDeviceName.current)
        )
        try persistAuth(response)
        UserDefaults.standard.set(normalizedEmail, forKey: Self.emailKey)
        try await bootstrap(accessToken: response.accessToken)
        if let token = KeychainSecret.load(account: Self.deviceTokenAccount) {
            try await register(deviceToken: token)
        }
    }

    func restoreAndRegisterIfPossible() async {
        guard let deviceToken = KeychainSecret.load(account: Self.deviceTokenAccount) else { return }
        do {
            try await register(deviceToken: deviceToken)
        } catch {
            // The registration will retry on the next APNs token callback or foreground sync.
        }
    }

    func register(deviceToken: String) async throws {
        try KeychainSecret.save(deviceToken, account: Self.deviceTokenAccount)
        let credential = try await validDeviceCredential()
        let response: RegistrationResponse = try await request(
            path: "/v1/push/devices",
            method: "POST",
            bearer: credential,
            body: RegistrationRequest(deviceToken: deviceToken)
        )
        stateVersion = response.stateVersion
    }

    func synchronize(
        isForeground: Bool,
        activeSessionID: String?,
        unreadSessionIDs: [String],
        mutedSessionIDs: [String]
    ) async {
        guard let deviceToken = KeychainSecret.load(account: Self.deviceTokenAccount) else { return }
        do {
            if stateVersion == nil {
                try await register(deviceToken: deviceToken)
            }
            try await sendState(
                deviceToken: deviceToken,
                isForeground: isForeground,
                activeSessionID: activeSessionID,
                unreadSessionIDs: unreadSessionIDs,
                mutedSessionIDs: mutedSessionIDs
            )
        } catch MobilePushError.conflict {
            do {
                try await register(deviceToken: deviceToken)
                try await sendState(
                    deviceToken: deviceToken,
                    isForeground: isForeground,
                    activeSessionID: activeSessionID,
                    unreadSessionIDs: unreadSessionIDs,
                    mutedSessionIDs: mutedSessionIDs
                )
            } catch { }
        } catch { }
    }

    func unregister() async {
        guard let credential = KeychainSecret.load(account: Self.credentialAccount) else {
            clearLocalState()
            return
        }
        let _: RemovalResponse? = try? await request(
            path: "/v1/push/client",
            method: "DELETE",
            bearer: credential,
            body: EmptyRequest()
        )
        clearLocalState()
    }

    private func sendState(
        deviceToken: String,
        isForeground: Bool,
        activeSessionID: String?,
        unreadSessionIDs: [String],
        mutedSessionIDs: [String]
    ) async throws {
        guard let expectedVersion = stateVersion else { throw MobilePushError.notProvisioned }
        let credential = try await validDeviceCredential()
        let response: StateResponse = try await request(
            path: "/v1/push/state",
            method: "PUT",
            bearer: credential,
            body: StateRequest(
                deviceToken: deviceToken,
                expectedVersion: expectedVersion,
                activeSessionID: activeSessionID,
                unreadSessionIDs: Array(Set(unreadSessionIDs)).sorted(),
                mutedSessionIDs: Array(Set(mutedSessionIDs)).sorted(),
                isForeground: isForeground
            )
        )
        stateVersion = response.stateVersion
    }

    private func validDeviceCredential() async throws -> String {
        if let credential = KeychainSecret.load(account: Self.credentialAccount) {
            return credential
        }
        let access = try await refreshedAccessToken()
        try await bootstrap(accessToken: access)
        guard let credential = KeychainSecret.load(account: Self.credentialAccount) else {
            throw MobilePushError.notProvisioned
        }
        return credential
    }

    private func refreshedAccessToken() async throws -> String {
        guard let refresh = KeychainSecret.load(account: Self.refreshAccount) else {
            throw MobilePushError.notProvisioned
        }
        let response: AuthResponse = try await request(
            path: "/v1/auth/refresh",
            method: "POST",
            bearer: nil,
            body: RefreshRequest(refreshToken: refresh)
        )
        try persistAuth(response)
        return response.accessToken
    }

    private func bootstrap(accessToken: String) async throws {
        let response: BootstrapResponse = try await request(
            path: "/v1/push/bootstrap",
            method: "POST",
            bearer: accessToken,
            body: BootstrapRequest(installationID: Self.installationID())
        )
        try KeychainSecret.save(response.credential, account: Self.credentialAccount)
        stateVersion = nil
    }

    private func persistAuth(_ response: AuthResponse) throws {
        accessToken = response.accessToken
        try KeychainSecret.save(response.refreshToken, account: Self.refreshAccount)
    }

    private func clearLocalState() {
        accessToken = nil
        stateVersion = nil
        KeychainSecret.delete(account: Self.refreshAccount)
        KeychainSecret.delete(account: Self.credentialAccount)
        KeychainSecret.delete(account: Self.deviceTokenAccount)
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
    }

    private static func installationID() -> String {
        if let existing = UserDefaults.standard.string(forKey: installationKey), UUID(uuidString: existing) != nil {
            return existing
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: installationKey)
        return value
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        bearer: String?,
        body: Body
    ) async throws -> Response {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, rawResponse) = try await URLSession.shared.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw MobilePushError.invalidResponse }
        if response.statusCode == 409 { throw MobilePushError.conflict }
        guard 200..<300 ~= response.statusCode else {
            if response.statusCode == 401, path.hasPrefix("/v1/push/") {
                KeychainSecret.delete(account: Self.credentialAccount)
            }
            throw MobilePushError.server(response.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct EmptyRequest: Encodable {}
private struct LoginRequest: Encodable { let email: String; let password: String; let deviceName: String }
private struct RefreshRequest: Encodable { let refreshToken: String }
private struct BootstrapRequest: Encodable { let installationID: String }
private struct RegistrationRequest: Encodable { let deviceToken: String }
private struct StateRequest: Encodable {
    let deviceToken: String
    let expectedVersion: Int
    let activeSessionID: String?
    let unreadSessionIDs: [String]
    let mutedSessionIDs: [String]
    let isForeground: Bool
}
private struct AuthResponse: Decodable { let accessToken: String; let refreshToken: String }
private struct BootstrapResponse: Decodable { let credential: String }
private struct RegistrationResponse: Decodable { let stateVersion: Int }
private struct StateResponse: Decodable { let stateVersion: Int }
private struct RemovalResponse: Decodable { let removed: Bool }

private enum MobilePushError: LocalizedError {
    case missingCredentials
    case notProvisioned
    case invalidResponse
    case conflict
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: "Enter your WHOX account email and password to enable notifications."
        case .notProvisioned: "Sign in to your WHOX account to enable notifications."
        case .invalidResponse: "The notification service returned an invalid response."
        case .conflict: "Notification state changed on another request."
        case .server(let status): "The notification service returned HTTP \(status)."
        }
    }
}

private enum UIDeviceName {
    static var current: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "Apple device"
        #endif
    }
}
