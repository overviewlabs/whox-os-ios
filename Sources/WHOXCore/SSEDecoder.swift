import Foundation

public struct ServerSentEvent: Equatable, Sendable {
    public let event: String?
    public let data: String
    public init(event: String?, data: String) { self.event = event; self.data = data }
}

public struct SSEDecoder: Sendable {
    private var buffer = Data()
    private var frameLines: [Data] = []
    public init() {}
    public mutating func feed(_ bytes: Data) throws -> [ServerSentEvent] {
        buffer.append(bytes)
        var result: [ServerSentEvent] = []
        while let line = popLine() {
            if line.isEmpty {
                if let event = parseFrame() { result.append(event) }
                frameLines.removeAll(keepingCapacity: true)
            } else {
                frameLines.append(line)
            }
        }
        return result
    }
    private mutating func popLine() -> Data? {
        guard let end = buffer.firstIndex(where: { $0 == 10 || $0 == 13 }) else { return nil }
        let line = Data(buffer[..<end])
        var upper = buffer.index(after: end)
        if buffer[end] == 13 {
            if upper == buffer.endIndex, !line.isEmpty { return nil }
            if upper < buffer.endIndex, buffer[upper] == 10 { upper = buffer.index(after: upper) }
        }
        buffer.removeSubrange(buffer.startIndex..<upper)
        return line
    }
    private func parseFrame() -> ServerSentEvent? {
        var name: String?; var data: [String] = []
        for bytes in frameLines {
            let raw = String(decoding: bytes, as: UTF8.self)[...]
            if raw.hasPrefix(":") { continue }
            if raw.hasPrefix("event:") { name = value(raw.dropFirst(6)) }
            else if raw.hasPrefix("data:") { data.append(value(raw.dropFirst(5))) }
        }
        return data.isEmpty ? nil : .init(event: name, data: data.joined(separator: "\n"))
    }
    private func value(_ v: Substring) -> String { v.first == " " ? String(v.dropFirst()) : String(v) }
}

public enum ChatStreamEvent: Sendable, Equatable { case delta(String), message(ChatMessage), session(String), error(String), done }
public struct ChatSSEParser: Sendable {
    private var decoder = SSEDecoder()
    public init() {}
    public mutating func feed(_ data: Data) throws -> [ChatStreamEvent] {
        try decoder.feed(data).flatMap { event -> [ChatStreamEvent] in
            if event.data == "[DONE]" || event.event == "done" { return [.done] }
            guard let bytes = event.data.data(using: .utf8) else { return [] }
            if event.event == nil, let message = try? JSONDecoder.whox.decode(ChatMessage.self, from: bytes) {
                return [.message(message)]
            }
            guard let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return [] }

            switch event.event {
            case "run.started":
                guard let session = (json["session_id"] ?? json["sessionId"]) as? String else { return [] }
                return [.session(session)]
            case "assistant.delta":
                guard let delta = (json["delta"] ?? json["content"] ?? json["text"]) as? String else { return [] }
                return [.delta(delta)]
            case "assistant.completed":
                guard
                    let id = (json["message_id"] ?? json["messageId"]) as? String,
                    let content = json["content"] as? String
                else { return [] }
                return [.message(ChatMessage(id: id, role: .assistant, content: content))]
            case "message.started", "tool.progress", "run.completed":
                return []
            default:
                var events: [ChatStreamEvent] = []
                if let session = (json["session_id"] ?? json["sessionId"]) as? String { events.append(.session(session)) }
                if let error = json["error"] as? String { events.append(.error(error)) }
                if let delta = (json["delta"] ?? json["content"] ?? json["text"]) as? String { events.append(.delta(delta)) }
                else if let nested = json["message"] as? [String: Any], let content = nested["content"] as? String { events.append(.delta(content)) }
                return events
            }
        }
    }
}
