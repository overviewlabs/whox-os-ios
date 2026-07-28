import Foundation

public enum ComposerTrailingControl: Equatable, Sendable {
    case microphone
    case liveAudio
    case send
    case stop
}

public enum ComposerContract {
    public static let containerHeight: Double = 48
    public static let trailingSlot: Double = 44

    public static func trailingControl(
        draft: String,
        isSending: Bool,
        isRecording: Bool
    ) -> ComposerTrailingControl {
        if isSending { return .stop }
        if isRecording { return .liveAudio }
        return draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .microphone : .send
    }
}
