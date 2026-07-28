import Testing
@testable import WHOXCore

@Test func messageBubblesUseReadableMaximumWithoutForcingShortMessagesWide() {
    #expect(ChatBubbleContract.maximumWidth(containerWidth: 390) == 312)
    #expect(ChatBubbleContract.maximumWidth(containerWidth: 1_024) == 480)
    #expect(ChatBubbleContract.fillsAvailableWidth(role: .user) == false)
    #expect(ChatBubbleContract.fillsAvailableWidth(role: .assistant) == true)
}

@Test func drawerGesturesOnlyOpenFromTheirMatchingScreenEdge() {
    #expect(DrawerGestureContract.openingSide(startX: 12, containerWidth: 390) == .leading)
    #expect(DrawerGestureContract.openingSide(startX: 378, containerWidth: 390) == .trailing)
    #expect(DrawerGestureContract.openingSide(startX: 100, containerWidth: 390) == nil)
}

@Test func drawerProjectionCommitsOpenAndCloseLikeAnInteractivePanel() {
    #expect(DrawerGestureContract.shouldCommit(translation: 130, predictedTranslation: 150, width: 300))
    #expect(DrawerGestureContract.shouldCommit(translation: 30, predictedTranslation: 55, width: 300) == false)
    #expect(DrawerGestureContract.shouldCommit(translation: -130, predictedTranslation: -150, width: 300))
}

@Test func trueRootPresentationUsesSlash() {
    #expect(DirectoryPathContract.displayPath("") == "/")
    #expect(DirectoryPathContract.displayPath("WHOX OS/Apple Developer") == "/WHOX OS/Apple Developer")
}
