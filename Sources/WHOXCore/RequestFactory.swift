import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WHOXRequestError: Error, Equatable {
    case invalidURL
}

public struct WHOXRequestFactory: Sendable {
    public let baseURL: URL
    private let accessToken: String

    public init(baseURL: URL, accessToken: String) {
        self.baseURL = baseURL
        self.accessToken = accessToken
    }

    public func listSessions(limit: Int = 50, offset: Int = 0) throws -> URLRequest {
        try request(
            path: "/api/sessions",
            method: "GET",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "offset", value: String(offset))
            ]
        )
    }

    public func startRun(input: String, sessionID: String) throws -> URLRequest {
        let body = try JSONSerialization.data(withJSONObject: [
            "input": input,
            "session_id": sessionID
        ])
        return try request(path: "/v1/runs", method: "POST", body: body)
    }

    private func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw WHOXRequestError.invalidURL
        }
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = basePath + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw WHOXRequestError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
