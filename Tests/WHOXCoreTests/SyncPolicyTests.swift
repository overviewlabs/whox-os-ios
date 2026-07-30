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

@Test func realtimeAndBackgroundRefreshCadenceStayWithinIOSLimits() {
    #expect(GatewaySyncPolicy.foregroundRefreshInterval == 5)
    #expect(GatewaySyncPolicy.minimumBackgroundRefreshInterval >= 15 * 60)
    #expect(GatewaySyncPolicy.backgroundTaskIdentifier == "com.whox.whoxos.session-refresh")
}
