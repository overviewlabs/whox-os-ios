import Foundation
import Testing
@testable import WHOXCore

@Test func decodesSessionListFromWHOXAPI() throws {
    let json = #"""
    {
      "object": "list",
      "data": [
        {
          "id": "api_123",
          "title": "Release WHOX OS",
          "source": "api_server",
          "model": "hermes-agent",
          "created_at": 1722081600,
          "last_active_at": 1722081660
        }
      ],
      "limit": 50,
      "offset": 0,
      "has_more": false
    }
    """#.data(using: .utf8)!

    let response = try JSONDecoder.whox.decode(SessionList.self, from: json)

    #expect(response.data.count == 1)
    #expect(response.data[0].id == "api_123")
    #expect(response.data[0].title == "Release WHOX OS")
    #expect(response.hasMore == false)
}

@Test func decodesRunApprovalEvent() throws {
    let json = #"""
    {
      "event": "approval.required",
      "run_id": "run_123",
      "timestamp": 1722081660,
      "tool_name": "terminal",
      "description": "Run a deployment command"
    }
    """#.data(using: .utf8)!

    let event = try JSONDecoder.whox.decode(RunEvent.self, from: json)

    #expect(event.kind == .approvalRequired)
    #expect(event.runID == "run_123")
    #expect(event.toolName == "terminal")
}

@Test func decodesPersistentChatAttachments() throws {
    let json = #"""
    {
      "id": "message-1",
      "role": "user",
      "content": "Describe this image",
      "attachments": [
        {
          "id": "00000000-0000-4000-8000-000000000021",
          "name": "dock.jpg",
          "mimeType": "image/jpeg",
          "size": 2048
        }
      ]
    }
    """#.data(using: .utf8)!

    let message = try JSONDecoder.whox.decode(ChatMessage.self, from: json)

    #expect(message.attachments.count == 1)
    #expect(message.attachments[0].name == "dock.jpg")
    #expect(message.attachments[0].mimeType == "image/jpeg")
    #expect(message.attachments[0].size == 2048)
}

@Test func missingChatAttachmentsDecodeAsEmpty() throws {
    let json = #"{"id":"message-2","role":"assistant","content":"Done"}"#.data(using: .utf8)!
    let message = try JSONDecoder.whox.decode(ChatMessage.self, from: json)
    #expect(message.attachments.isEmpty)
}
