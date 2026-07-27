import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import WHOXCore

@Test func decodesLiveSessionAndMessageSchemas() throws {
    let sessionsJSON = #"{"object":"list","data":[{"id":"s_1","title":"Gateway redesign","source":"api_server","last_active":1785153000.5,"started_at":1785150000,"message_count":3,"preview":"Ship the app","model":"gpt-5.6"}]}"#.data(using: .utf8)!
    let response = try JSONDecoder.whox.decode(SessionList.self, from: sessionsJSON)
    let session = try #require(response.data.first)
    #expect(session.lastActive == 1785153000.5)
    #expect(session.startedAt == 1785150000)
    #expect(session.messageCount == 3)
    #expect(session.preview == "Ship the app")

    let messagesJSON = #"{"object":"list","session_id":"s_1","data":[{"id":17,"session_id":"s_1","role":"assistant","content":"**Ready.**","timestamp":1785153001,"reasoning":"checked","reasoning_content":"checked","tool_calls":[{"name":"terminal","status":"completed"}],"finish_reason":"stop"}]}"#.data(using: .utf8)!
    let messages = try JSONDecoder.whox.decode(MessageList.self, from: messagesJSON)
    #expect(messages.sessionID == "s_1")
    #expect(messages.data.first?.id == "17")
    #expect(messages.data.first?.role == .assistant)
    #expect(messages.data.first?.toolCalls?.first?.name == "terminal")

    let decoder = JSONDecoder.whox
    let rolePayload = { (role: String) in
        #"{"id":18,"role":"\#(role)","content":"metadata","timestamp":1785153002}"#.data(using: .utf8)!
    }
    #expect(try decoder.decode(ChatMessage.self, from: rolePayload("tool")).role == .tool)
    #expect(try decoder.decode(ChatMessage.self, from: rolePayload("session_meta")).role == .sessionMeta)
    #expect(try decoder.decode(ChatMessage.self, from: rolePayload("future_role")).role == .other("future_role"))
}

@Test func decodesCreateSessionChatAndJobsSchemas() throws {
    let created = try JSONDecoder.whox.decode(CreateSessionResponse.self, from: #"{"object":"session","session":{"id":"s_2","title":"New chat","source":"api_server"}}"#.data(using: .utf8)!)
    #expect(created.session.id == "s_2")

    let chat = try JSONDecoder.whox.decode(ChatResponse.self, from: #"{"object":"chat.completion","session_id":"s_2","message":{"id":"m_2","role":"assistant","content":"Hello","timestamp":1785153001},"usage":{"input_tokens":8,"output_tokens":2}}"#.data(using: .utf8)!)
    #expect(chat.message.content == "Hello")
    #expect(chat.usage?.outputTokens == 2)

    let jobs = try JSONDecoder.whox.decode(JobList.self, from: #"{"jobs":[{"id":"j_1","name":"Morning brief","schedule":{"kind":"cron","expr":"0 8 * * *"},"schedule_display":"0 8 * * *","state":"scheduled","enabled":true,"prompt":"Summarize news","created_at":"2026-07-27T13:00:00Z","next_run_at":"2026-07-28T12:00:00Z"}]}"#.data(using: .utf8)!)
    #expect(jobs.jobs.first?.name == "Morning brief")
    #expect(jobs.jobs.first?.scheduleDisplay == "0 8 * * *")
    #expect(jobs.jobs.first?.state == "scheduled")
}

@Test func buildsEveryGatewayRouteWithoutDuplicatingBasePath() throws {
    let factory = WHOXRequestFactory(baseURL: URL(string: "https://mobile-api.whox.ai")!, accessToken: "short-lived")
    #expect(try factory.listSessions(limit: 100, offset: 0).url?.absoluteString == "https://mobile-api.whox.ai/v1/sessions?limit=100&offset=0")
    #expect(try factory.sessionMessages("s/one").url?.absoluteString == "https://mobile-api.whox.ai/v1/sessions/s%2Fone/messages")
    #expect(try factory.createSession(title: "Launch").url?.path == "/v1/sessions")
    #expect(try factory.updateSession("s1", title: "Renamed").httpMethod == "PATCH")
    #expect(try factory.deleteSession("s1").httpMethod == "DELETE")
    #expect(try factory.chat(sessionID: "s1", message: "Hello", stream: false).url?.path == "/v1/sessions/s1/chat")
    #expect(try factory.chat(sessionID: "s1", message: "Hello", stream: true).url?.path == "/v1/sessions/s1/chat/stream")
    #expect(try factory.listJobs().url?.path == "/v1/jobs")
    #expect(try factory.jobAction("j1", action: .pause).url?.path == "/v1/jobs/j1/pause")
    #expect(try factory.capabilities().url?.path == "/v1/capabilities")
    #expect(try factory.skills().url?.path == "/v1/skills")
    #expect(try factory.toolsets().url?.path == "/v1/toolsets")
    #expect(try factory.models().url?.path == "/v1/models")
    #expect(try factory.health().url?.path == "/v1/health")
    #expect(try factory.health().value(forHTTPHeaderField: "Authorization") == "Bearer short-lived")
}

@Test func parsesTypedChatSSEAcrossChunksAndDoneSentinel() throws {
    var parser = ChatSSEParser()
    #expect(try parser.feed(Data("data: {\"delta\":\"Hel".utf8)).isEmpty)
    let events = try parser.feed(Data("lo\"}\r\n\r\nevent: done\r\ndata: [DONE]\r\n\r\n".utf8))
    #expect(events == [.delta("Hello"), .done])
}
