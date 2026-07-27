import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WHOXRequestError: Error, Equatable { case invalidURL }
public enum JobAction: String, Sendable { case pause, resume, run }

public struct WHOXRequestFactory: Sendable {
    public let baseURL: URL
    private let accessToken: String
    public init(baseURL: URL, accessToken: String) { self.baseURL = baseURL; self.accessToken = accessToken }

    public func listSessions(limit: Int = 100, offset: Int = 0) throws -> URLRequest { try request(path: "/v1/sessions", queryItems: [.init(name: "limit", value: String(limit)), .init(name: "offset", value: String(offset))]) }
    public func createSession(title: String) throws -> URLRequest { try jsonRequest(path: "/v1/sessions", method: "POST", object: ["title": title, "source": "api_server"]) }
    public func sessionMessages(_ id: String) throws -> URLRequest { try request(path: "/v1/sessions/\(escaped(id))/messages") }
    public func updateSession(_ id: String, title: String) throws -> URLRequest { try jsonRequest(path: "/v1/sessions/\(escaped(id))", method: "PATCH", object: ["title": title]) }
    public func deleteSession(_ id: String) throws -> URLRequest { try request(path: "/v1/sessions/\(escaped(id))", method: "DELETE") }
    public func startRun(input: String, sessionID: String) throws -> URLRequest { try jsonRequest(path: "/v1/runs", method: "POST", object: ["input": input, "session_id": sessionID]) }
    public func chat(sessionID: String, message: String, stream: Bool = true) throws -> URLRequest {
        let suffix = stream ? "/chat/stream" : "/chat"
        var r = try jsonRequest(path: "/v1/sessions/\(escaped(sessionID))\(suffix)", method: "POST", object: ["message": message])
        if stream { r.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        return r
    }
    public func listJobs() throws -> URLRequest { try request(path: "/v1/jobs") }
    public func createJob(name: String, schedule: String, prompt: String) throws -> URLRequest { try jsonRequest(path: "/v1/jobs", method: "POST", object: ["name": name, "schedule": schedule, "prompt": prompt]) }
    public func deleteJob(_ id: String) throws -> URLRequest { try request(path: "/v1/jobs/\(escaped(id))", method: "DELETE") }
    public func jobAction(_ id: String, action: JobAction) throws -> URLRequest { try request(path: "/v1/jobs/\(escaped(id))/\(action.rawValue)", method: "POST") }
    public func capabilities() throws -> URLRequest { try request(path: "/v1/capabilities") }
    public func skills() throws -> URLRequest { try request(path: "/v1/skills") }
    public func toolsets() throws -> URLRequest { try request(path: "/v1/toolsets") }
    public func models() throws -> URLRequest { try request(path: "/v1/models") }
    public func health() throws -> URLRequest { try request(path: "/v1/health") }

    private func escaped(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? value }
    private func jsonRequest(path: String, method: String, object: [String: String]) throws -> URLRequest { try request(path: path, method: method, body: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) }
    private func request(path: String, method: String = "GET", queryItems: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw WHOXRequestError.invalidURL }
        let root = components.percentEncodedPath.hasSuffix("/") ? String(components.percentEncodedPath.dropLast()) : components.percentEncodedPath
        components.percentEncodedPath = root + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw WHOXRequestError.invalidURL }
        var r = URLRequest(url: url); r.httpMethod = method; r.timeoutInterval = 30
        r.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { r.httpBody = body; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }
}
