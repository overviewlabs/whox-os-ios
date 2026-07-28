import Foundation

public extension JSONDecoder {
    static var whox: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

public struct SessionList: Decodable, Sendable {
    public let object: String
    public let data: [WHOXSession]
    public let limit: Int?
    public let offset: Int?
    public let hasMore: Bool?
}

public struct WHOXSession: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public var title: String?
    public let source: String?
    public let model: String?
    public let lastActive: Double?
    public let startedAt: Double?
    public let messageCount: Int?
    public let preview: String?
    public let createdAt: Double?
    public let lastActiveAt: Double?

    public init(id: String, title: String? = nil, source: String? = nil, model: String? = nil, lastActive: Double? = nil, startedAt: Double? = nil, messageCount: Int? = nil, preview: String? = nil, createdAt: Double? = nil, lastActiveAt: Double? = nil) {
        self.id = id; self.title = title; self.source = source; self.model = model
        self.lastActive = lastActive; self.startedAt = startedAt; self.messageCount = messageCount
        self.preview = preview; self.createdAt = createdAt; self.lastActiveAt = lastActiveAt
    }

    public var activityTimestamp: Double { lastActive ?? lastActiveAt ?? startedAt ?? createdAt ?? 0 }
}

public struct CreateSessionResponse: Decodable, Sendable { public let object: String; public let session: WHOXSession }

public struct DirectoryListing: Decodable, Sendable, Equatable {
    public let object: String
    public let path: String
    public let parent: String?
    public let data: [DirectoryEntry]

    public init(object: String = "list", path: String, parent: String?, data: [DirectoryEntry]) {
        self.object = object
        self.path = path
        self.parent = parent
        self.data = data
    }
}

public struct DirectoryEntry: Decodable, Identifiable, Sendable, Equatable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int?
    public let modifiedAt: Double

    public init(path: String, name: String, isDirectory: Bool, size: Int?, modifiedAt: Double) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public struct MessageList: Decodable, Sendable {
    public let object: String
    public let sessionID: String
    public let data: [ChatMessage]
    private enum CodingKeys: String, CodingKey { case object, sessionID = "sessionId", data }
}

public enum MessageRole: Codable, Sendable, Equatable {
    case user, assistant, system, tool, sessionMeta, other(String)
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "user": self = .user
        case "assistant": self = .assistant
        case "system": self = .system
        case "tool": self = .tool
        case "session_meta": self = .sessionMeta
        default: self = .other(value)
        }
    }
    public func encode(to encoder: Encoder) throws {
        let value: String
        switch self {
        case .user: value = "user"
        case .assistant: value = "assistant"
        case .system: value = "system"
        case .tool: value = "tool"
        case .sessionMeta: value = "session_meta"
        case .other(let raw): value = raw
        }
        var container = encoder.singleValueContainer(); try container.encode(value)
    }
    public var displayName: String {
        switch self {
        case .sessionMeta: "Session"
        case .other(let value): value.replacingOccurrences(of: "_", with: " ").capitalized
        default: String(describing: self).capitalized
        }
    }
}

public struct ToolCall: Codable, Sendable, Equatable {
    public let id: String?
    public let name: String?
    public let status: String?
    public let arguments: JSONValue?
    public let result: JSONValue?
}

public struct ChatAttachment: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let mimeType: String
    public let size: Int

    public init(id: String, name: String, mimeType: String, size: Int) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.size = size
    }

    public var isImage: Bool { mimeType.hasPrefix("image/") }
}

public struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let sessionID: String?
    public let role: MessageRole
    public var content: String
    public let timestamp: Double?
    public let reasoning: String?
    public let reasoningContent: String?
    public let toolCalls: [ToolCall]?
    public let toolName: String?
    public let toolCallID: String?
    public let finishReason: String?
    public let tokenCount: Int?
    public let attachments: [ChatAttachment]
    public init(id: String, sessionID: String? = nil, role: MessageRole, content: String, timestamp: Double? = nil, reasoning: String? = nil, reasoningContent: String? = nil, toolCalls: [ToolCall]? = nil, toolName: String? = nil, toolCallID: String? = nil, finishReason: String? = nil, tokenCount: Int? = nil, attachments: [ChatAttachment] = []) {
        self.id = id; self.sessionID = sessionID; self.role = role; self.content = content; self.timestamp = timestamp
        self.reasoning = reasoning; self.reasoningContent = reasoningContent; self.toolCalls = toolCalls
        self.toolName = toolName; self.toolCallID = toolCallID; self.finishReason = finishReason; self.tokenCount = tokenCount
        self.attachments = attachments
    }
    private enum CodingKeys: String, CodingKey { case id, sessionID = "sessionId", role, content, timestamp, reasoning, reasoningContent, toolCalls, toolName, toolCallID, finishReason, tokenCount, attachments }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? c.decode(String.self, forKey: .id) { id = value }
        else if let value = try? c.decode(Int.self, forKey: .id) { id = String(value) }
        else { id = "transient-\(UUID().uuidString.lowercased())" }
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID)
        role = try c.decode(MessageRole.self, forKey: .role)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        timestamp = try c.decodeIfPresent(Double.self, forKey: .timestamp)
        reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning)
        reasoningContent = try c.decodeIfPresent(String.self, forKey: .reasoningContent)
        toolCalls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        toolCallID = try c.decodeIfPresent(String.self, forKey: .toolCallID)
        finishReason = try c.decodeIfPresent(String.self, forKey: .finishReason)
        tokenCount = try c.decodeIfPresent(Int.self, forKey: .tokenCount)
        attachments = try c.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encodeIfPresent(sessionID, forKey: .sessionID); try c.encode(role, forKey: .role); try c.encode(content, forKey: .content)
        try c.encodeIfPresent(timestamp, forKey: .timestamp); try c.encodeIfPresent(reasoning, forKey: .reasoning); try c.encodeIfPresent(reasoningContent, forKey: .reasoningContent)
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls); try c.encodeIfPresent(toolName, forKey: .toolName); try c.encodeIfPresent(toolCallID, forKey: .toolCallID)
        try c.encodeIfPresent(finishReason, forKey: .finishReason); try c.encodeIfPresent(tokenCount, forKey: .tokenCount)
        if !attachments.isEmpty { try c.encode(attachments, forKey: .attachments) }
    }
}

public struct TokenUsage: Codable, Sendable, Equatable { public let inputTokens: Int?; public let outputTokens: Int?; public let totalTokens: Int? }
public struct ChatResponse: Decodable, Sendable {
    public let object: String
    public let sessionID: String
    public let message: ChatMessage
    public let usage: TokenUsage?
    private enum CodingKeys: String, CodingKey { case object, sessionID = "sessionId", message, usage }
}

public struct JobList: Decodable, Sendable { public let jobs: [ScheduledJob] }
public struct ScheduledJob: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let schedule: JSONValue?
    public let scheduleDisplay: String?
    public let state: String?
    public let enabled: Bool?
    public let prompt: String?
    public let nextRunAt: String?
    public let lastRunAt: String?
    public let createdAt: String?
    public let lastStatus: String?
    public let lastError: String?
    public var statusText: String { enabled == false ? "paused" : (state ?? lastStatus ?? "unknown") }
}

public indirect enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .string(let v): try c.encode(v); case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v); case .object(let v): try c.encode(v); case .array(let v): try c.encode(v); case .null: try c.encodeNil() }
    }
    public var displayString: String {
        switch self { case .string(let v): return v; case .number(let v): return String(v); case .bool(let v): return String(v); case .null: return "null"; case .array, .object: return (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? "" }
    }
}

public enum RunEventKind: String, Decodable, Sendable { case runStarted = "run.started", runCompleted = "run.completed", runFailed = "run.failed", runCancelled = "run.cancelled", messageStarted = "message.started", messageDelta = "message.delta", assistantCompleted = "assistant.completed", toolStarted = "tool.started", toolProgress = "tool.progress", toolCompleted = "tool.completed", toolFailed = "tool.failed", approvalRequired = "approval.required", approvalResponded = "approval.responded", error, done }
public struct RunEvent: Decodable, Sendable {
    public let kind: RunEventKind; public let runID: String?; public let timestamp: Double?; public let toolName: String?; public let description: String?; public let delta: String?; public let output: String?; public let error: String?
    private enum CodingKeys: String, CodingKey { case kind = "event", runID = "runId", timestamp, toolName, description, delta, output, error }
}
