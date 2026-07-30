import SwiftUI

@main
struct WHOXOSApp: App {
    @State private var store = MessageStore()
    @State private var gatewayConfiguration = GatewayConfiguration()

    var body: some Scene {
        WindowGroup {
            MessagesListView()
                .environment(store)
                .environment(gatewayConfiguration)
        }
    }
}
