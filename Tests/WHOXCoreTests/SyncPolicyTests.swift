import Foundation
import Testing
@testable import WHOXCore

@Test func automaticSyncNeverBlocksAUsableScreen() {
    #expect(GatewaySyncPolicy.presentation(for: .launch, hasCachedSnapshot: true) == .silent)
    #expect(GatewaySyncPolicy.presentation(for: .foreground, hasCachedSnapshot: true) == .silent)
    #expect(GatewaySyncPolicy.presentation(for: .periodic, hasCachedSnapshot: true) == .silent)
    #expect(GatewaySyncPolicy.presentation(for: .background, hasCachedSnapshot: true) == .silent)
}

@Test func firstConnectionCanShowProgressUntilThereIsAUsableSnapshot() {
    #expect(GatewaySyncPolicy.presentation(for: .manualConnection, hasCachedSnapshot: false) == .blocking)
    #expect(GatewaySyncPolicy.presentation(for: .manualConnection, hasCachedSnapshot: true) == .silent)
}

@Test func failedAutomaticSyncOnlyReopensSetupWithoutAUsableSnapshot() {
    #expect(GatewaySyncPolicy.shouldPresentConnectionError(trigger: .launch, hasCachedSnapshot: false))
    #expect(GatewaySyncPolicy.shouldPresentConnectionError(trigger: .foreground, hasCachedSnapshot: false))
    #expect(!GatewaySyncPolicy.shouldPresentConnectionError(trigger: .periodic, hasCachedSnapshot: true))
    #expect(GatewaySyncPolicy.shouldPresentConnectionError(trigger: .manualConnection, hasCachedSnapshot: true))
}

@Test func queuedManualSyncCannotCommitAfterDisconnectAdvancesGeneration() {
    #expect(GatewaySyncPolicy.canCommit(startedGeneration: 7, currentGeneration: 7))
    #expect(!GatewaySyncPolicy.canCommit(startedGeneration: 7, currentGeneration: 8))
}

@Test func sessionIndexRefreshDoesNotFetchEveryTranscript() {
    let plan = GatewaySessionLoadPlan.indexRefresh(
        sessionIDs: ["s1", "s2", "s3"]
    )

    #expect(plan.sessionIDs == ["s1", "s2", "s3"])
    #expect(plan.messageSessionIDs.isEmpty)
}

@Test func openingASessionFetchesOnlyItsTranscript() {
    let plan = GatewaySessionLoadPlan.openSession("s2")

    #expect(plan.sessionIDs.isEmpty)
    #expect(plan.messageSessionIDs == ["s2"])
}

@Test func onlyNewAPISessionsRequireInternalHelperInspection() {
    #expect(GatewaySyncPolicy.shouldInspectPotentialHelper(source: "api_server", isKnownSession: false))
    #expect(!GatewaySyncPolicy.shouldInspectPotentialHelper(source: "api_server", isKnownSession: true))
    #expect(!GatewaySyncPolicy.shouldInspectPotentialHelper(source: "cli", isKnownSession: false))
}

@Test func metadataActivityMarksInactiveSessionsUnread() {
    #expect(GatewaySyncPolicy.isUnread(
        previousActivity: 10,
        currentActivity: 11,
        isActive: false,
        wasUnread: false
    ))
    #expect(!GatewaySyncPolicy.isUnread(
        previousActivity: 10,
        currentActivity: 11,
        isActive: true,
        wasUnread: false
    ))
    #expect(GatewaySyncPolicy.isUnread(
        previousActivity: 11,
        currentActivity: 11,
        isActive: false,
        wasUnread: true
    ))
}

@Test func realtimeAndBackgroundRefreshCadenceStayWithinIOSLimits() {
    #expect(GatewaySyncPolicy.foregroundRefreshInterval == 5)
    #expect(GatewaySyncPolicy.minimumBackgroundRefreshInterval >= 15 * 60)
    #expect(GatewaySyncPolicy.backgroundTaskIdentifier == "com.whox.whoxos.session-refresh")
}
