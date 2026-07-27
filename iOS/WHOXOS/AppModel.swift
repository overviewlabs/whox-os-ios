import Foundation
import Observation
import WHOXCore

@MainActor
@Observable
final class AppModel {
    enum Connection: Equatable {
        case unpaired
        case connecting
        case connected(serverName: String)
        case failed(message: String)
    }

    var connection: Connection = .unpaired
    var sessions: [WHOXSession] = []
    var selectedSessionID: String?
    var activeRunID: String?
    var pendingApproval: RunEvent?

    var selectedSession: WHOXSession? {
        sessions.first { $0.id == selectedSessionID }
    }
}
