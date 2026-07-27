import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import WHOXCore

@Test func buildsAuthenticatedSessionListRequest() throws {
    let factory = WHOXRequestFactory(
        baseURL: URL(string: "https://mobile-api.whox.ai")!,
        accessToken: "mobile-access-token"
    )

    let request = try factory.listSessions(limit: 25, offset: 50)

    #expect(request.httpMethod == "GET")
    #expect(request.url?.absoluteString == "https://mobile-api.whox.ai/v1/sessions?limit=25&offset=50")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mobile-access-token")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
}

@Test func buildsRunRequestWithoutServerCredential() throws {
    let factory = WHOXRequestFactory(
        baseURL: URL(string: "https://mobile-api.whox.ai")!,
        accessToken: "mobile-access-token"
    )

    let request = try factory.startRun(input: "Check server health", sessionID: "ios-main")
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])

    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/v1/runs")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(json["input"] == "Check server health")
    #expect(json["session_id"] == "ios-main")
    #expect(!String(decoding: body, as: UTF8.self).contains("API_SERVER_KEY"))
}
