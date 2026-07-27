import Foundation
import WHOXCore

enum GatewayError: LocalizedError {
    case invalidResponse
    case server(Int, String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "WHOX OS returned an invalid response."
        case .server(let code, let message): message.isEmpty ? "Gateway request failed (\(code))." : message
        }
    }
}

actor GatewayService {
    private let baseURL = URL(string: "https://mobile-api.whox.ai")!
    private let auth: AuthenticationService
    private let session: URLSession
    init(auth: AuthenticationService, session: URLSession = .shared) { self.auth = auth; self.session = session }

    func sessions() async throws -> [WHOXSession] { let r: SessionList = try await decode { try $0.listSessions() }; return r.data }
    func messages(_ id: String) async throws -> [ChatMessage] { let r: MessageList = try await decode { try $0.sessionMessages(id) }; return r.data }
    func createSession(title: String) async throws -> WHOXSession { let r: CreateSessionResponse = try await decode { try $0.createSession(title: title) }; return r.session }
    func renameSession(_ id: String, title: String) async throws { _ = try await raw { try $0.updateSession(id, title: title) } }
    func deleteSession(_ id: String) async throws { _ = try await raw { try $0.deleteSession(id) } }
    func jobs() async throws -> [ScheduledJob] { let r: JobList = try await decode { try $0.listJobs() }; return r.jobs }
    func createJob(name: String, schedule: String, prompt: String) async throws { _ = try await raw { try $0.createJob(name: name, schedule: schedule, prompt: prompt) } }
    func deleteJob(_ id: String) async throws { _ = try await raw { try $0.deleteJob(id) } }
    func jobAction(_ id: String, _ action: JobAction) async throws { _ = try await raw { try $0.jobAction(id, action: action) } }
    func capabilities() async throws -> JSONValue { try await decode { try $0.capabilities() } }
    func skills() async throws -> JSONValue { try await decode { try $0.skills() } }
    func toolsets() async throws -> JSONValue { try await decode { try $0.toolsets() } }
    func models() async throws -> JSONValue { try await decode { try $0.models() } }
    func health() async throws -> JSONValue { try await decode { try $0.health() } }

    func streamChat(sessionID: String, message: String, onEvent: @MainActor @escaping (ChatStreamEvent) -> Void) async throws {
        for attempt in 0...1 {
            try Task.checkCancellation()
            let token = try await auth.accessToken(refresh: attempt == 1)
            let request = try WHOXRequestFactory(baseURL: baseURL, accessToken: token).chat(sessionID: sessionID, message: message)
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
            if http.statusCode == 401 {
                if attempt == 0 { continue }
                throw AuthenticationError.sessionExpired
            }
            guard (200..<300).contains(http.statusCode) else { throw GatewayError.server(http.statusCode, "Chat request failed.") }
            var parser = ChatSSEParser()
            for try await byte in bytes {
                try Task.checkCancellation()
                for event in try parser.feed(Data([byte])) { await onEvent(event) }
            }
            return
        }
        throw AuthenticationError.sessionExpired
    }

    private func decode<T: Decodable>(_ build: (WHOXRequestFactory) throws -> URLRequest) async throws -> T {
        try JSONDecoder.whox.decode(T.self, from: try await raw(build))
    }
    private func raw(_ build: (WHOXRequestFactory) throws -> URLRequest) async throws -> Data {
        for attempt in 0...1 {
            let token = try await auth.accessToken(refresh: attempt == 1)
            let request = try build(WHOXRequestFactory(baseURL: baseURL, accessToken: token))
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
            if http.statusCode == 401 {
                if attempt == 0 { continue }
                throw AuthenticationError.sessionExpired
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode([String: String].self, from: data)["error"]) ?? ""
                throw GatewayError.server(http.statusCode, message)
            }
            return data
        }
        throw AuthenticationError.sessionExpired
    }
}
