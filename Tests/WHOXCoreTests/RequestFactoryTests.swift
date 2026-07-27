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

@Test func buildsBinaryAttachmentUploadRequest() throws {
    let factory = WHOXRequestFactory(
        baseURL: URL(string: "https://mobile-api.whox.ai")!,
        accessToken: "mobile-access-token"
    )
    let bytes = Data([0x25, 0x50, 0x44, 0x46])

    let request = try factory.upload(
        attachmentID: "70d2a3e8-9fc8-4c66-b5dc-cf61b9c19cc2",
        filename: "Q3 freight plan.pdf",
        mimeType: "application/pdf",
        data: bytes
    )

    #expect(request.httpMethod == "PUT")
    #expect(request.url?.path == "/v1/uploads/70d2a3e8-9fc8-4c66-b5dc-cf61b9c19cc2")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mobile-access-token")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/pdf")
    #expect(request.value(forHTTPHeaderField: "X-WHOX-Filename") == "Q3%20freight%20plan.pdf")
    #expect(request.httpBody == bytes)
}

@Test func chatRequestCarriesUploadedAttachmentReferencesAndTurnID() throws {
    let factory = WHOXRequestFactory(
        baseURL: URL(string: "https://mobile-api.whox.ai")!,
        accessToken: "mobile-access-token"
    )

    let request = try factory.chat(
        sessionID: "ios-main",
        message: "Summarize these",
        attachmentIDs: ["image-id", "document-id"],
        requestID: "00000000-0000-4000-8000-000000000014"
    )
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(json["message"] as? String == "Summarize these")
    #expect(json["attachment_ids"] as? [String] == ["image-id", "document-id"])
    #expect(request.url?.path == "/v1/sessions/ios-main/chat/stream")
    #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    #expect(request.value(forHTTPHeaderField: "X-WHOX-Turn-ID") == "00000000-0000-4000-8000-000000000014")
}

@Test func buildsCompleteChatRequestWhenStreamingIsDisabled() throws {
    let factory = WHOXRequestFactory(
        baseURL: URL(string: "https://mobile-api.whox.ai")!,
        accessToken: "mobile-access-token"
    )

    let request = try factory.chat(sessionID: "ios-main", message: "Hello", stream: false)

    #expect(request.url?.path == "/v1/sessions/ios-main/chat")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
}
