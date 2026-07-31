import Foundation
import UIKit
import UserNotifications
import WHOXCore

extension Notification.Name {
    static let openWHOXSession = Notification.Name("com.whox.whoxos.open-session")
}

private final class NotificationRuntimeState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeSessionID: String?
    private var mutedSessionIDs: Set<String> = []
    private var seenEvents: [String: Date] = [:]
    private var pendingSessionID: String?

    func update(activeSessionID: String?, mutedSessionIDs: [String]) {
        lock.withLock {
            self.activeSessionID = activeSessionID
            self.mutedSessionIDs = Set(mutedSessionIDs)
        }
    }

    func shouldPresent(sessionID: String?, eventID: String) -> Bool {
        lock.withLock {
            let cutoff = Date().addingTimeInterval(-600)
            seenEvents = seenEvents.filter { $0.value >= cutoff }
            guard seenEvents[eventID] == nil else { return false }
            seenEvents[eventID] = Date()
            guard let sessionID, !sessionID.isEmpty else { return true }
            return sessionID != activeSessionID && !mutedSessionIDs.contains(sessionID)
        }
    }

    func stagePendingSessionID(_ sessionID: String?) {
        guard let sessionID, !sessionID.isEmpty else { return }
        lock.withLock { pendingSessionID = sessionID }
    }

    func consumePendingSessionID() -> String? {
        lock.withLock {
            defer { pendingSessionID = nil }
            return pendingSessionID
        }
    }
}

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    private let center = UNUserNotificationCenter.current()
    nonisolated private let runtimeState = NotificationRuntimeState()

    func configure() {
        center.delegate = self
    }

    func requestAuthorizationAndRegister() async {
        let settings = await center.notificationSettings()
        let authorized: Bool
        switch settings.authorizationStatus {
        case .notDetermined:
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
        case .authorized, .provisional, .ephemeral:
            authorized = true
        case .denied:
            authorized = false
        @unknown default:
            authorized = false
        }
        if authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        Task {
            try? await MobilePushRelay.shared.register(deviceToken: token)
        }
    }

    func didFailToRegister(error: Error) {
        #if DEBUG
        print("Remote notification registration failed: \(error.localizedDescription)")
        #endif
    }

    func synchronize(
        isForeground: Bool,
        activeSessionID: String?,
        unreadSessionIDs: [String],
        mutedSessionIDs: [String]
    ) {
        runtimeState.update(
            activeSessionID: isForeground ? activeSessionID : nil,
            mutedSessionIDs: mutedSessionIDs
        )
        let badgeCount = GatewayNotificationPolicy.badgeCount(unreadSessionIDs: unreadSessionIDs)
        Task { try? await center.setBadgeCount(badgeCount) }
        Task {
            await MobilePushRelay.shared.synchronize(
                isForeground: isForeground,
                activeSessionID: activeSessionID,
                unreadSessionIDs: unreadSessionIDs,
                mutedSessionIDs: mutedSessionIDs
            )
        }
    }

    func unregister() {
        runtimeState.update(activeSessionID: nil, mutedSessionIDs: [])
        Task { await MobilePushRelay.shared.unregister() }
    }

    func consumePendingSessionID() -> String? {
        runtimeState.consumePendingSessionID()
    }

    func deliverBackgroundFallback(for conversations: [Conversation], badgeCount: Int) async {
        let deliveredIDs = Set(await center.deliveredNotifications().map(\.request.identifier))
        let pendingIDs = Set(await center.pendingNotificationRequests().map(\.identifier))
        let existingIDs = deliveredIDs.union(pendingIDs)

        for conversation in conversations {
            guard let activityTimestamp = conversation.activityTimestamp else { continue }
            let activityID = String(Int64(activityTimestamp * 1_000))
            let identifier = "background-fallback.\(conversation.id).\(activityID)"
            guard !existingIDs.contains(identifier) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "New WHOX OS message"
            content.body = "A session has new activity."
            content.sound = .default
            content.badge = NSNumber(value: badgeCount)
            content.threadIdentifier = conversation.id
            content.userInfo = [
                "sessionID": conversation.id,
                "eventID": identifier,
            ]
            try? await center.add(
                UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            )
        }
        try? await center.setBadgeCount(badgeCount)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        let sessionID = userInfo["sessionID"] as? String
        let eventID = (userInfo["eventID"] as? String) ?? notification.request.identifier
        guard runtimeState.shouldPresent(sessionID: sessionID, eventID: eventID) else {
            completionHandler([.badge])
            return
        }
        completionHandler([.banner, .list, .sound, .badge])
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionID = response.notification.request.content.userInfo["sessionID"] as? String
        runtimeState.stagePendingSessionID(sessionID)
        Task { @MainActor in
            if let sessionID, !sessionID.isEmpty {
                NotificationCenter.default.post(name: .openWHOXSession, object: sessionID)
            }
        }
        completionHandler()
    }
}
