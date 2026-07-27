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
    public let limit: Int
    public let offset: Int
    public let hasMore: Bool
}

public struct WHOXSession: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String?
    public let source: String?
    public let model: String?
    public let createdAt: Double?
    public let lastActiveAt: Double?
}

public enum RunEventKind: String, Decodable, Sendable {
    case runStarted = "run.started"
    case runCompleted = "run.completed"
    case runFailed = "run.failed"
    case runCancelled = "run.cancelled"
    case messageStarted = "message.started"
    case messageDelta = "message.delta"
    case assistantCompleted = "assistant.completed"
    case toolStarted = "tool.started"
    case toolProgress = "tool.progress"
    case toolCompleted = "tool.completed"
    case toolFailed = "tool.failed"
    case approvalRequired = "approval.required"
    case approvalResponded = "approval.responded"
    case error
    case done
}

public struct RunEvent: Decodable, Sendable {
    public let kind: RunEventKind
    public let runID: String?
    public let timestamp: Double?
    public let toolName: String?
    public let description: String?
    public let delta: String?
    public let output: String?
    public let error: String?

    private enum CodingKeys: String, CodingKey {
        case kind = "event"
        case runID = "runId"
        case timestamp
        case toolName
        case description
        case delta
        case output
        case error
    }
}
