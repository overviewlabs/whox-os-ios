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
