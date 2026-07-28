import Testing
import Foundation
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

@Test func drawerPresentationMatchesTheRevealedFullHeightPanelStyle() {
    #expect(DrawerPresentationContract.width(containerWidth: 390) == 304.2)
    #expect(DrawerPresentationContract.width(containerWidth: 1_024) == 390)
    #expect(DrawerPresentationContract.mainOffset(side: .leading, progress: 1, width: 300) == 300)
    #expect(DrawerPresentationContract.mainOffset(side: .trailing, progress: 1, width: 300) == -300)
}

@Test func linkReferencesAcceptOnlyUniqueHTTPURLsAndProduceMessageContext() {
    let links = LinkReferenceContract.validLinks(from: """
    https://example.com/report
    HTTP://example.org/a?q=1
    https://example.com/report
    ftp://example.com/file
    not a link
    """)
    #expect(links == ["https://example.com/report", "HTTP://example.org/a?q=1"])
    #expect(LinkReferenceContract.messageText(draft: "Compare these", links: links) == """
    Compare these

    Reference links:
    - https://example.com/report
    - HTTP://example.org/a?q=1
    """)
}

@Test func previewFilenamesCannotEscapeTheirTemporaryDirectory() {
    #expect(PreviewFilenameContract.safeFilename("report.pdf") == "report.pdf")
    #expect(PreviewFilenameContract.safeFilename("../../Library/state") == nil)
    #expect(PreviewFilenameContract.safeFilename("folder\\secret.txt") == nil)
    #expect(PreviewFilenameContract.safeFilename(".") == nil)
}
