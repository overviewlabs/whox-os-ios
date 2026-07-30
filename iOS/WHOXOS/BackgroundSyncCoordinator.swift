import BackgroundTasks
import UIKit
import WHOXCore

private final class BackgroundTaskCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private let task: BGTask
    private var completed = false

    init(task: BGTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}

@MainActor
final class BackgroundSyncCoordinator {
    static let shared = BackgroundSyncCoordinator()

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: GatewaySyncPolicy.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await self.run(refreshTask)
            }
        }
    }


    func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: GatewaySyncPolicy.backgroundTaskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: GatewaySyncPolicy.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(
            timeIntervalSinceNow: GatewaySyncPolicy.minimumBackgroundRefreshInterval
        )
        try? BGTaskScheduler.shared.submit(request)
    }

    private func run(_ backgroundTask: BGAppRefreshTask) async {
        schedule()
        let completion = BackgroundTaskCompletionGate(task: backgroundTask)
        let refresh = Task { @MainActor in
            await self.performRefresh()
        }
        backgroundTask.expirationHandler = {
            refresh.cancel()
            completion.complete(success: false)
        }
        let succeeded = await refresh.value
        completion.complete(success: succeeded && !refresh.isCancelled)
    }

    private func performRefresh() async -> Bool {
        let gatewayConfiguration = GatewayConfiguration()
        guard gatewayConfiguration.isConfigured else { return false }
        do {
            let client = try gatewayConfiguration.client()
            let store = MessageStore()
            try await store.connect(to: client, trigger: .background)
            return true
        } catch {
            return false
        }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundSyncCoordinator.shared.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundSyncCoordinator.shared.schedule()
    }
}
