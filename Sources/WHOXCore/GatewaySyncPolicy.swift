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

    public static func canImportPotentialHelper(
        source: String?,
        inspectionSucceeded: Bool
    ) -> Bool {
        source != "api_server" || inspectionSucceeded
    }

    public static func descendants(
        of roots: Set<String>,
        parentBySessionID: [String: String]
    ) -> Set<String> {
        var result = roots
        var changed = true
        while changed {
            changed = false
            for (sessionID, parentID) in parentBySessionID
                where !result.contains(sessionID) && result.contains(parentID) {
                result.insert(sessionID)
                changed = true
            }
        }
        return result
    }

    public static func isUnread(
        previousActivity: Double?,
        currentActivity: Double,
        isActive: Bool,
        wasUnread: Bool,
        consumesReadBaseline: Bool = false
    ) -> Bool {
        guard !isActive, !consumesReadBaseline else { return false }
        guard let previousActivity else { return wasUnread }
        return wasUnread || currentActivity > previousActivity
    }
}
