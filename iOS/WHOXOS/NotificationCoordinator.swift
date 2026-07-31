import Foundation
import UIKit
import UserNotifications
import WHOXCore

extension Notification.Name {
    static let openWHOXSession = Notification.Name("com.whox.whoxos.open-session")
}

private struct PushDeviceBody: Encodable {
    let deviceToken: String
}

private struct PushStateBody: Encodable, Equatable {
    let deviceToken: String
    let isForeground: Bool
    let activeSessionID: String?
    let unreadSessionIDs: [String]
    let mutedSessionIDs: [String]
}

private struct PushNotificationClient: Sendable {
    private let baseURL = URL(string: "https://mobile-api.whox.ai")!
    let gatewayKey: String

    func register(deviceToken: String) async throws {
        try await send(path: "/v1/push/devices", method: "POST", body: PushDeviceBody(deviceToken: deviceToken))
    }

    func update(state: PushStateBody) async throws {
        try await send(path: "/v1/push/state", method: "PUT", body: state)
    }

    func unregister(deviceToken: String) async throws {
        try await send(path: "/v1/push/devices", method: "DELETE", body: PushDeviceBody(deviceToken: deviceToken))
    }

    private func send<Body: Encodable>(path: String, method: String, body: Body) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(gatewayKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }
}

@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    private let center = UNUserNotificationCenter.current()
    private var deviceToken: String?
    private var lastState: PushStateBody?
    private var lastPresenceSentAt = Date.distantPast
    private var synchronizationTask: Task<Void, Never>?
    private var pendingSessionID: String?

    func requestAuthorizationAndRegister() async {
        center.delegate = self
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
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        lastState = nil
    }

    func didFailToRegister(error: Error) {
        #if DEBUG
        print("Remote notification registration failed: \(error.localizedDescription)")
        #endif
    }

    func synchronize(
        gatewayKey: String,
        isForeground: Bool,
        activeSessionID: String?,
        unreadSessionIDs: [String],
        mutedSessionIDs: [String]
    ) {
        let uniqueUnread = Array(Set(unreadSessionIDs)).sorted()
        let badgeCount = GatewayNotificationPolicy.badgeCount(unreadSessionIDs: uniqueUnread)
        Task {
            try? await center.setBadgeCount(badgeCount)
        }

        guard let deviceToken, !gatewayKey.isEmpty else { return }
        let state = PushStateBody(
            deviceToken: deviceToken,
            isForeground: isForeground,
            activeSessionID: isForeground ? activeSessionID : nil,
            unreadSessionIDs: uniqueUnread,
            mutedSessionIDs: Array(Set(mutedSessionIDs)).sorted()
        )
        let now = Date()
        guard state != lastState || now.timeIntervalSince(lastPresenceSentAt) >= 25 else { return }
        lastState = state
        lastPresenceSentAt = now
        synchronizationTask?.cancel()
        synchronizationTask = Task {
            do {
                let client = PushNotificationClient(gatewayKey: gatewayKey)
                try await client.register(deviceToken: deviceToken)
                try Task.checkCancellation()
                try await client.update(state: state)
            } catch is CancellationError {
                return
            } catch {
                #if DEBUG
                print("Push state synchronization failed: \(error.localizedDescription)")
                #endif
                lastState = nil
            }
        }
    }

    func unregister(gatewayKey: String) {
        guard let deviceToken, !gatewayKey.isEmpty else { return }
        synchronizationTask?.cancel()
        Task {
            try? await PushNotificationClient(gatewayKey: gatewayKey).unregister(deviceToken: deviceToken)
        }
        lastState = nil
    }

    func consumePendingSessionID() -> String? {
        defer { pendingSessionID = nil }
        return pendingSessionID
    }

    func deliverBackgroundFallback(for conversations: [Conversation], badgeCount: Int) async {
        guard !conversations.isEmpty else {
            try? await center.setBadgeCount(badgeCount)
            return
        }
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        let existingSessionIDs = Set(
            delivered.compactMap { $0.request.content.userInfo["sessionID"] as? String } +
                pending.compactMap { $0.content.userInfo["sessionID"] as? String }
        )
        for conversation in conversations where !existingSessionIDs.contains(conversation.id) {
            let content = UNMutableNotificationContent()
            content.title = "New WHOX OS message"
            content.body = conversation.preview.isEmpty ? "A session has a new message." : conversation.preview
            content.sound = .default
            content.badge = NSNumber(value: badgeCount)
            content.threadIdentifier = conversation.id
            content.userInfo = ["sessionID": conversation.id]
            let request = UNNotificationRequest(
                identifier: "background-fallback.\(conversation.id)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
        try? await center.setBadgeCount(badgeCount)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            completionHandler([.banner, .list, .sound, .badge])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionID = response.notification.request.content.userInfo["sessionID"] as? String
        Task { @MainActor in
            if let sessionID, !sessionID.isEmpty {
                pendingSessionID = sessionID
                NotificationCenter.default.post(name: .openWHOXSession, object: sessionID)
            }
            completionHandler()
        }
    }
}
