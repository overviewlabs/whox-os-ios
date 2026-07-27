import Testing
@testable import WHOXCore

@Test func hidesInternalTranscriptRoles() {
    #expect(ChatPresentation.isVisible(.user))
    #expect(ChatPresentation.isVisible(.assistant))
    #expect(!ChatPresentation.isVisible(.tool))
    #expect(!ChatPresentation.isVisible(.system))
    #expect(!ChatPresentation.isVisible(.sessionMeta))
    #expect(!ChatPresentation.isVisible(.other("developer")))
}

@Test func sanitizesInjectedTimestampAndAttachmentPaths() {
    let raw = "[Sun 2026-07-26 18:45:09 EDT] Describe this image[Image attached at: /root/WHOX OS/.hermes/cache/images/example.jpg] [screenshot]"
    #expect(ChatPresentation.sanitizeUserContent(raw) == "Describe this image\n\n📎 example.jpg")

    let current = "[User sent an image: /WHOX OS/Mobile Users/uploads/private/dock.png]\nLook at this"
    #expect(ChatPresentation.sanitizeUserContent(current) == "📎 dock.png\n\nLook at this")
}

@Test func parsesMarkdownIntoSemanticChatBlocks() {
    let source = """
    ## Summary

    This is the first paragraph.

    - Secure uploads
    - Clear spacing

    1. Open Settings
    2. Toggle streaming

    > A useful note

    ```swift
    let enabled = true
    ```
    """

    #expect(ChatPresentation.blocks(source) == [
        .heading(level: 2, text: "Summary"),
        .paragraph("This is the first paragraph."),
        .unorderedList(["Secure uploads", "Clear spacing"]),
        .orderedList(["Open Settings", "Toggle streaming"]),
        .quote("A useful note"),
        .code(language: "swift", content: "let enabled = true")
    ])
}

@Test func preservesSoftWrappedParagraphLines() {
    #expect(ChatPresentation.blocks("One line\ncontinues here.") == [.paragraph("One line\ncontinues here.")])
}
