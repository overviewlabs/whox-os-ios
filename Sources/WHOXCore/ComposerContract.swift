import Foundation

public enum ComposerTrailingControl: Equatable, Sendable {
    case microphone
    case liveAudio
    case finalizing
    case send
    case stop
}

public enum ComposerContract {
    public static let containerHeight: Double = 48
    public static let trailingSlot: Double = 44

    public static func trailingControl(
        draft: String,
        hasReferences: Bool = false,
        isSending: Bool,
        isRecording: Bool,
        isFinalizing: Bool = false
    ) -> ComposerTrailingControl {
        if isSending { return .stop }
        if isRecording { return .liveAudio }
        if isFinalizing { return .finalizing }
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || hasReferences ? .send : .microphone
    }
}

public enum VoiceCapturePolicy {
    public static func shouldCancelForRouteChange(reasonRawValue: UInt) -> Bool {
        [2, 7, 8].contains(reasonRawValue)
    }
}

public enum DirectoryFailureDisposition: Equatable, Sendable {
    case ignore
    case authentication
    case presentation
}

public enum DirectoryFailurePolicy {
    public static func disposition(
        accountIsCurrent: Bool,
        requestIsCurrent: Bool,
        authenticationExpired: Bool
    ) -> DirectoryFailureDisposition {
        guard accountIsCurrent else { return .ignore }
        if authenticationExpired { return .authentication }
        return requestIsCurrent ? .presentation : .ignore
    }
}
