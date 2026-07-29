import Foundation
import Testing
@testable import WHOXCore

@Test func parsesIncrementalSSEFramesAndIgnoresKeepalive() throws {
    var decoder = SSEDecoder()

    let first = try decoder.feed(Data(": keepalive\n\nevent: progress\ndata: {\"event\":\"message.delta\",\"delta\":\"Hel".utf8))
    #expect(first.isEmpty)

    let second = try decoder.feed(Data("lo\"}\n\ndata: {\"event\":\"run.completed\"}\n\n".utf8))

    #expect(second.count == 2)
    #expect(second[0].event == "progress")
    #expect(second[0].data.contains("Hello"))
    #expect(second[1].event == nil)
}

@Test func joinsMultipleDataLines() throws {
    var decoder = SSEDecoder()
    let events = try decoder.feed(Data("data: first\ndata: second\n\n".utf8))

    #expect(events == [ServerSentEvent(event: nil, data: "first\nsecond")])
}

@Test func preservesUTF8ScalarsSplitAcrossFeeds() throws {
    var decoder = SSEDecoder()
    var events: [ServerSentEvent] = []
    for byte in Data("data: {\"delta\":\"🙂\"}\n\n".utf8) {
        events += try decoder.feed(Data([byte]))
    }
    #expect(events == [ServerSentEvent(event: nil, data: "{\"delta\":\"🙂\"}")])
}

@Test func waitsForCompleteCRLFBoundary() throws {
    var decoder = SSEDecoder()
    #expect(try decoder.feed(Data("data: first\r".utf8)).isEmpty)
    #expect(try decoder.feed(Data("\n\r".utf8)) == [ServerSentEvent(event: nil, data: "first")])
    #expect(try decoder.feed(Data("\n".utf8)).isEmpty)
}

@Test func acceptsMixedSSELineEndings() throws {
    var decoder = SSEDecoder()
    #expect(try decoder.feed(Data("data: one\n\r\n".utf8)) == [ServerSentEvent(event: nil, data: "one")])
    #expect(try decoder.feed(Data("data: two\r\n\r".utf8)) == [ServerSentEvent(event: nil, data: "two")])
}

@Test func emitsSessionAndDeltaFromTheSameFrame() throws {
    var parser = ChatSSEParser()
    let events = try parser.feed(Data("data: {\"session_id\":\"s1\",\"delta\":\"Hello\"}\n\n".utf8))
    #expect(events == [.session("s1"), .delta("Hello")])
}

@Test func typedGatewayStreamEmitsSanitizedActivityAndReplacesPartialTextWithCompletion() throws {
    var parser = ChatSSEParser()
    let stream = """
    event: run.started
    data: {"session_id":"s1"}

    event: assistant.delta
    data: {"message_id":"m1","delta":"SH"}

    event: assistant.delta
    data: {"message_id":"m1","delta":"APE_OK"}

    event: activity.progress
    data: {"id":"call-1","kind":"files","label":"Inspecting files"}

    event: tool.progress
    data: {"tool_name":"_thinking","delta":"SHAPE_OK"}

    event: assistant.completed
    data: {"session_id":"s1","message_id":"m1","content":"SHAPE_OK","completed":true}

    event: done
    data: {"session_id":"s1"}

    """

    let events = try parser.feed(Data((stream + "\n").utf8))

    #expect(events == [
        .session("s1"),
        .delta("SH"),
        .delta("APE_OK"),
        .activity(ChatActivity(id: "call-1", kind: "files", label: "Inspecting files")),
        .message(ChatMessage(id: "m1", role: .assistant, content: "SHAPE_OK")),
        .done,
    ])
}

@Test func assistantCompletionPreservesGeneratedAttachments() throws {
    var parser = ChatSSEParser()
    let stream = """
    event: assistant.completed
    data: {"message_id":"m-media","role":"assistant","content":"Here is the image.","attachments":[{"id":"attachment-1","name":"cake.png","mimeType":"image/png","size":1234}]}

    """

    let events = try parser.feed(Data((stream + "\n").utf8))

    #expect(events == [
        .message(ChatMessage(
            id: "m-media",
            role: .assistant,
            content: "Here is the image.",
            attachments: [ChatAttachment(id: "attachment-1", name: "cake.png", mimeType: "image/png", size: 1234)]
        )),
    ])
}
