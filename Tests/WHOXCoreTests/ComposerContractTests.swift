import Testing
@testable import WHOXCore

@Test func composerTrailingControlChangesWithoutChangingGeometry() {
    #expect(ComposerContract.trailingControl(draft: "", isSending: false, isRecording: false) == .microphone)
    #expect(ComposerContract.trailingControl(draft: "", hasReferences: true, isSending: false, isRecording: false) == .send)
    #expect(ComposerContract.trailingControl(draft: "", isSending: false, isRecording: true) == .liveAudio)
    #expect(ComposerContract.trailingControl(draft: "Hi", isSending: false, isRecording: false) == .send)
    #expect(ComposerContract.trailingControl(draft: "Hi", isSending: true, isRecording: false) == .stop)
    #expect(ComposerContract.trailingControl(draft: "Hi", isSending: false, isRecording: false, isFinalizing: true) == .finalizing)
    #expect(ComposerContract.containerHeight == 48)
    #expect(ComposerContract.trailingSlot == 44)
}

@Test func voiceCapturePolicyIgnoresCategoryOnlyRouteChanges() {
    #expect(!VoiceCapturePolicy.shouldCancelForRouteChange(reasonRawValue: 3))
    #expect(VoiceCapturePolicy.shouldCancelForRouteChange(reasonRawValue: 2))
    #expect(VoiceCapturePolicy.shouldCancelForRouteChange(reasonRawValue: 7))
}

@Test func supersededDirectoryExpiryStillSignsOutCurrentAccount() {
    #expect(DirectoryFailurePolicy.disposition(
        accountIsCurrent: true,
        requestIsCurrent: false,
        authenticationExpired: true
    ) == .authentication)
    #expect(DirectoryFailurePolicy.disposition(
        accountIsCurrent: true,
        requestIsCurrent: false,
        authenticationExpired: false
    ) == .ignore)
}
