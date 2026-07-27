import Foundation

public struct ServerSentEvent: Equatable, Sendable {
    public let event: String?
    public let data: String

    public init(event: String?, data: String) {
        self.event = event
        self.data = data
    }
}

public struct SSEDecoder: Sendable {
    private var buffer = ""

    public init() {}

    public mutating func feed(_ bytes: Data) throws -> [ServerSentEvent] {
        buffer.append(String(decoding: bytes, as: UTF8.self))
        buffer = buffer.replacingOccurrences(of: "\r\n", with: "\n")

        var events: [ServerSentEvent] = []
        while let boundary = buffer.range(of: "\n\n") {
            let frame = String(buffer[..<boundary.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<boundary.upperBound)
            if let event = parse(frame) {
                events.append(event)
            }
        }
        return events
    }

    private func parse(_ frame: String) -> ServerSentEvent? {
        var eventName: String?
        var dataLines: [String] = []

        for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") { continue }
            if line.hasPrefix("event:") {
                eventName = fieldValue(line.dropFirst("event:".count))
            } else if line.hasPrefix("data:") {
                dataLines.append(fieldValue(line.dropFirst("data:".count)))
            }
        }

        guard !dataLines.isEmpty else { return nil }
        return ServerSentEvent(event: eventName, data: dataLines.joined(separator: "\n"))
    }

    private func fieldValue(_ value: Substring) -> String {
        value.first == " " ? String(value.dropFirst()) : String(value)
    }
}
