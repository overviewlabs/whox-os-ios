import Testing
@testable import WHOXCore

@Test func composerTrailingControlChangesWithoutChangingGeometry() {
    #expect(ComposerContract.trailingControl(draft: "", isSending: false, isRecording: false) == .microphone)
    #expect(ComposerContract.trailingControl(draft: "", isSending: false, isRecording: true) == .liveAudio)
    #expect(ComposerContract.trailingControl(draft: "Hi", isSending: false, isRecording: false) == .send)
    #expect(ComposerContract.trailingControl(draft: "Hi", isSending: true, isRecording: false) == .stop)
    #expect(ComposerContract.containerHeight == 48)
    #expect(ComposerContract.trailingSlot == 44)
}
