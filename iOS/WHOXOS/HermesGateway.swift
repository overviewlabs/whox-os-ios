import Foundation
import Observation
import Security

struct HermesSessionList: Decodable, Sendable {
    let data: [HermesSession]
    let hasMore: Bool?

    private enum CodingKeys: String, CodingKey {
        case data, sessions, hasMore
    }

    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var sessions: [HermesSession] = []
            while !unkeyed.isAtEnd {
                sessions.append(try unkeyed.decode(HermesSession.self))
            }
            data = sessions
            hasMore = false
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = (try? container.decode([HermesSession].self, forKey: .data))
            ?? (try? container.decode([HermesSession].self, forKey: .sessions))
            ?? []
        hasMore = try? container.decodeIfPresent(Bool.self, forKey: .hasMore)
    }
}

struct HermesSession: Decodable, Sendable {
    let id: String
    let title: String?
    let source: String?
    let model: String?
    let lastActive: Double?
    let startedAt: Double?
    let messageCount: Int?
    let preview: String?
    let createdAt: Double?
    let lastActiveAt: Double?
    let parentSessionID: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, source, model, lastActive, startedAt, messageCount, preview, createdAt,
            lastActiveAt
        case parentSessionID = "parentSessionId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let integerID = try? container.decode(Int.self, forKey: .id) {
            id = String(integerID)
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Session has no ID")
            )
        }
        title = container.lossyString(forKey: .title)
        source = container.lossyString(forKey: .source)
        model = container.lossyString(forKey: .model)
        lastActive = container.lossyDouble(forKey: .lastActive)
        startedAt = container.lossyDouble(forKey: .startedAt)
        messageCount = container.lossyInt(forKey: .messageCount)
        preview = container.lossyString(forKey: .preview)
        createdAt = container.lossyDouble(forKey: .createdAt)
        lastActiveAt = container.lossyDouble(forKey: .lastActiveAt)
        parentSessionID = container.lossyString(forKey: .parentSessionID)
    }

    var activityTimestamp: Double {
        lastActive ?? lastActiveAt ?? startedAt ?? createdAt ?? 0
    }
}

struct HermesMessageList: Decodable, Sendable {
    let data: [HermesMessage]
}

struct HermesMessage: Decodable, Sendable {
    let id: String
    let role: String
    let content: String
    let timestamp: Double?

    private enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let integerID = try? container.decode(Int.self, forKey: .id) {
            id = String(integerID)
        } else {
            id = "message-\(UUID().uuidString.lowercased())"
        }
        role = container.lossyString(forKey: .role) ?? "assistant"
        if let text = try? container.decode(String.self, forKey: .content) {
            content = text
        } else if let parts = try? container.decode([HermesContentPart].self, forKey: .content) {
            content = parts.compactMap(\.text).joined(separator: "\n")
        } else {
            content = ""
        }
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
    }
}

private struct HermesContentPart: Decodable {
    let text: String?
}

private extension KeyedDecodingContainer {
    func lossyString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func lossyDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func lossyInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}

private struct HermesCreatedSession: Decodable {
    let session: HermesSession
}

private struct HermesChatResponse: Decodable {
    let message: HermesMessage
}

enum HermesGatewayError: LocalizedError {
    case invalidURL
    case insecureURL
    case invalidResponse
    case server(status: Int, message: String)
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid gateway URL."
        case .insecureURL:
            "Use an HTTPS gateway URL so the API key and agent data stay encrypted."
        case .invalidResponse:
            "The gateway returned an unreadable response."
        case .server(let status, let message):
            "Gateway error \(status): \(message)"
        case .missingConfiguration:
            "Connect a Hermes gateway first."
        }
    }
}

struct HermesGatewayClient: Sendable {
    let baseURL: URL
    let apiKey: String

    func listAllSessions() async throws -> [HermesSession] {
        var sessions: [HermesSession] = []
        var offset = 0
        let limit = 100

        for _ in 0..<100 {
            let response: HermesSessionList = try await send(
                path: "/api/sessions",
                queryItems: [
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "offset", value: String(offset)),
                    URLQueryItem(name: "include_children", value: "true"),
                ]
            )
            sessions.append(contentsOf: response.data)
            guard response.hasMore == true || response.data.count == limit else { break }
            offset += response.data.count
            guard !response.data.isEmpty else { break }
        }

        return sessions.sorted { $0.activityTimestamp > $1.activityTimestamp }
    }

    func messages(sessionID: String) async throws -> [HermesMessage] {
        let response: HermesMessageList = try await send(
            path: "/api/sessions/\(escaped(sessionID))/messages"
        )
        return response.data
    }

    func session(_ sessionID: String) async throws -> HermesSession {
        let response: HermesCreatedSession = try await send(
            path: "/api/sessions/\(escaped(sessionID))"
        )
        return response.session
    }

    func createSession() async throws -> HermesSession {
        let response: HermesCreatedSession = try await send(
            path: "/api/sessions",
            method: "POST",
            body: ["source": "api_server"]
        )
        return response.session
    }

    func deleteSession(_ sessionID: String) async throws {
        try await sendWithoutBody(
            path: "/api/sessions/\(escaped(sessionID))",
            method: "DELETE"
        )
    }

    func chat(sessionID: String, input: String) async throws -> HermesMessage {
        let response: HermesChatResponse = try await send(
            path: "/api/sessions/\(escaped(sessionID))/chat",
            method: "POST",
            body: ["input": input]
        )
        return response.message
    }

    func updateSessionTitle(_ sessionID: String, title: String) async throws {
        let _: HermesCreatedSession = try await send(
            path: "/api/sessions/\(escaped(sessionID))",
            method: "PATCH",
            body: ["title": title]
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: [String: String]? = nil
    ) async throws -> Response {
        let bodyData = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        let request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            bodyData: bodyData
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw HermesGatewayError.invalidResponse
        }
    }

    private func sendWithoutBody(path: String, method: String) async throws {
        let request = try makeRequest(path: path, method: method, queryItems: [], bodyData: nil)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        bodyData: Data?
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw HermesGatewayError.invalidURL
        }
        let root = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast())
            : components.percentEncodedPath
        components.percentEncodedPath = root + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw HermesGatewayError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = method == "POST" ? 60 * 60 : 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw HermesGatewayError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            let message = error?["message"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw HermesGatewayError.server(status: response.statusCode, message: message)
        }
    }

    private func escaped(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        ) ?? value
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

@MainActor
@Observable
final class GatewayConfiguration {
    private static let urlKey = "hermes.gateway.url"
    private static let keychainAccount = "hermes-api-key"

    var gatewayURL: String {
        didSet { UserDefaults.standard.set(gatewayURL, forKey: Self.urlKey) }
    }
    var apiKey = ""
    var isConnecting = false
    var errorMessage: String?

    init() {
        gatewayURL = UserDefaults.standard.string(forKey: Self.urlKey) ?? ""
        apiKey = KeychainSecret.load(account: Self.keychainAccount) ?? ""
    }

    var isConfigured: Bool {
        !gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !apiKey.isEmpty
    }

    func client(url rawURL: String? = nil, key rawKey: String? = nil) throws -> HermesGatewayClient {
        let urlString = (rawURL ?? gatewayURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (rawKey ?? apiKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let enteredURL = URL(string: urlString), enteredURL.host != nil else {
            throw HermesGatewayError.invalidURL
        }
        guard enteredURL.scheme?.lowercased() == "https" else {
            throw HermesGatewayError.insecureURL
        }
        guard !key.isEmpty else { throw HermesGatewayError.missingConfiguration }
        return HermesGatewayClient(baseURL: Self.normalizedBaseURL(enteredURL), apiKey: key)
    }

    func save(url: String, key: String) throws {
        let client = try client(url: url, key: key)
        gatewayURL = client.baseURL.absoluteString
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try KeychainSecret.save(apiKey, account: Self.keychainAccount)
        errorMessage = nil
    }

    func disconnect() {
        gatewayURL = ""
        apiKey = ""
        errorMessage = nil
        KeychainSecret.delete(account: Self.keychainAccount)
    }

    private static func normalizedBaseURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let last = parts.last?.lowercased(), last == "v1" || last == "api" {
            parts.removeLast()
        }
        components.path = parts.isEmpty ? "" : "/" + parts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }
}

private enum KeychainSecret {
    private static let service = "com.whox.whoxos.gateway"

    static func save(_ value: String, account: String) throws {
        delete(account: account)
        let status = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ] as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw HermesGatewayError.server(status: Int(status), message: "Could not save the API key.")
        }
    }

    static func load(account: String) -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        SecItemUpdate(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ] as CFDictionary,
            [
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as CFDictionary
        )
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
