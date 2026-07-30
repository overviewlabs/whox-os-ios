import Foundation

public enum GatewaySyncTrigger: Sendable, Equatable {
    case launch
    case foreground
    case periodic
    case background
    case manualConnection
}

public enum GatewaySyncPresentation: Sendable, Equatable {
    case silent
    case blocking
}

public struct GatewaySessionLoadPlan: Sendable, Equatable {
    public let sessionIDs: [String]
    public let messageSessionIDs: [String]

    public static func indexRefresh(sessionIDs: [String]) -> Self {
        Self(sessionIDs: sessionIDs, messageSessionIDs: [])
    }

    public static func openSession(_ sessionID: String) -> Self {
        Self(sessionIDs: [], messageSessionIDs: [sessionID])
    }
}

public enum GatewaySyncPolicy {
    public static let foregroundRefreshInterval: TimeInterval = 5
    public static let minimumBackgroundRefreshInterval: TimeInterval = 15 * 60
    public static let backgroundTaskIdentifier = "com.whox.whoxos.session-refresh"

    public static func presentation(
        for trigger: GatewaySyncTrigger,
        hasCachedSnapshot: Bool
    ) -> GatewaySyncPresentation {
        guard trigger == .manualConnection, !hasCachedSnapshot else { return .silent }
        return .blocking
    }

    public static func shouldPresentConnectionError(
        trigger: GatewaySyncTrigger,
        hasCachedSnapshot: Bool
    ) -> Bool {
        trigger == .manualConnection || !hasCachedSnapshot
    }

    public static func canCommit(startedGeneration: Int, currentGeneration: Int) -> Bool {
        startedGeneration == currentGeneration
    }

    public static func shouldInspectPotentialHelper(
        source: String?,
        isKnownSession: Bool
    ) -> Bool {
        !isKnownSession && source == "api_server"
    }

    public static func isUnread(
        previousActivity: Double?,
        currentActivity: Double,
        isActive: Bool,
        wasUnread: Bool
    ) -> Bool {
        guard !isActive else { return false }
        guard let previousActivity else { return wasUnread }
        return wasUnread || currentActivity > previousActivity
    }
}
