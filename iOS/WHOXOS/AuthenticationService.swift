import Foundation
import Security

struct AuthenticatedUser: Codable, Equatable, Sendable {
    let id: String
    let email: String
    let role: String
}

struct AuthenticationSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: AuthenticatedUser
}

enum AuthenticationError: LocalizedError, Equatable {
    case invalidCredentials
    case rateLimited
    case sessionExpired
    case unavailable
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Email or password is incorrect."
        case .rateLimited:
            "Too many sign-in attempts. Please wait and try again."
        case .sessionExpired:
            "Your session expired. Please sign in again."
        case .unavailable:
            "WHOX sign-in is temporarily unavailable."
        case .keychain:
            "The secure session could not be saved on this iPhone."
        }
    }
}

actor AuthenticationService {
    private struct LoginRequest: Encodable {
        let email: String
        let password: String
        let deviceName: String
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String
    }

    private struct ServerError: Decodable {
        let error: String
    }

    private let baseURL = URL(string: "https://mobile-api.whox.ai/v1/auth")!
    private let keychain = RefreshTokenStore()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func signIn(email: String, password: String) async throws -> AuthenticationSession {
        let payload = LoginRequest(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            password: password,
            deviceName: "WHOX OS for iPhone"
        )
        let session: AuthenticationSession = try await send(path: "login", body: payload)
        try keychain.save(session.refreshToken)
        return session
    }

    func restoreSession() async throws -> AuthenticationSession? {
        guard let refreshToken = try keychain.read() else { return nil }
        do {
            let session: AuthenticationSession = try await send(
                path: "refresh",
                body: RefreshRequest(refreshToken: refreshToken)
            )
            try keychain.save(session.refreshToken)
            return session
        } catch {
            try? keychain.delete()
            throw error
        }
    }

    func signOut() async {
        let refreshToken: String?
        do {
            refreshToken = try keychain.read()
        } catch {
            return
        }
        defer { try? keychain.delete() }
        guard let refreshToken else { return }
        let _: SignOutResponse? = try? await send(
            path: "logout",
            body: RefreshRequest(refreshToken: refreshToken)
        )
    }

    private func send<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        request.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthenticationError.unavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw AuthenticationError.unavailable
        }
        guard (200..<300).contains(http.statusCode) else {
            let serverError = try? decoder.decode(ServerError.self, from: data)
            switch (http.statusCode, serverError?.error) {
            case (401, "invalid_credentials"):
                throw AuthenticationError.invalidCredentials
            case (401, "invalid_refresh_token"):
                throw AuthenticationError.sessionExpired
            case (429, _):
                throw AuthenticationError.rateLimited
            default:
                throw AuthenticationError.unavailable
            }
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AuthenticationError.unavailable
        }
    }
}

private struct SignOutResponse: Decodable {
    let status: String
}

private struct RefreshTokenStore: Sendable {
    private let service = "com.whox.whoxos.mobile-auth"
    private let account = "refresh-token"

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            insertion.merge(attributes) { _, new in new }
            let insertionStatus = SecItemAdd(insertion as CFDictionary, nil)
            guard insertionStatus == errSecSuccess else {
                throw AuthenticationError.keychain(insertionStatus)
            }
        } else if status != errSecSuccess {
            throw AuthenticationError.keychain(status)
        }
    }

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            throw AuthenticationError.keychain(status)
        }
        return token
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationError.keychain(status)
        }
    }
}
