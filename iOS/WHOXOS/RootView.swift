import SwiftUI

struct RootView: View {
    @State private var selection: AppTab = .chat

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { ChatHomeView() }
                .tabItem { Label("Chat", systemImage: "message.fill") }
                .tag(AppTab.chat)

            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "waveform.path.ecg") }
                .tag(AppTab.activity)

            NavigationStack { ControlCenterView() }
                .tabItem { Label("Control", systemImage: "switch.2") }
                .tag(AppTab.control)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(WHOXTheme.accent)
    }
}

private enum AppTab: Hashable {
    case chat, activity, control, settings
}
