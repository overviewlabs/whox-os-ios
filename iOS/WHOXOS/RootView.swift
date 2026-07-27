import SwiftUI

enum AppDestination: Hashable { case chat, library, projects, scheduled, plugins, remote, images, health, settings }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var destination: AppDestination = .chat
    @State private var isDrawerOpen = false

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--visual-review-settings") {
            _destination = State(initialValue: .settings)
        }
#endif
    }

    var body: some View {
        Group {
            switch model.authenticationState {
            case .checking: ZStack { WHOXTheme.background.ignoresSafeArea(); ProgressView() }
            case .signedOut: LoginView()
            case .signedIn: authenticatedContent
            }
        }
        .task { await model.restoreAuthenticationIfNeeded() }
    }

    private var authenticatedContent: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.78, 360)
            ZStack(alignment: .leading) {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(isDrawerOpen)
                if isDrawerOpen {
                    Color.black.opacity(0.28).ignoresSafeArea().onTapGesture { closeDrawer() }.transition(.opacity)
                    NavigationDrawer(onSelect: select)
                        .frame(width: width).transition(.move(edge: .leading))
                        .shadow(color: .black.opacity(0.18), radius: 18, x: 8)
                }
            }
            .animation(.snappy(duration: 0.28), value: isDrawerOpen)
        }
    }

    @ViewBuilder private var mainContent: some View {
        switch destination {
        case .chat: ChatHomeView(onOpenDrawer: openDrawer)
        case .library: FeatureNavigation(title: "Library", openDrawer: openDrawer) { LibraryView() }
        case .projects: FeatureNavigation(title: "Projects", openDrawer: openDrawer) { ProjectsView() }
        case .scheduled: FeatureNavigation(title: "Scheduled", openDrawer: openDrawer) { ScheduledView() }
        case .plugins: FeatureNavigation(title: "Plugins", openDrawer: openDrawer) { PluginsView() }
        case .remote: FeatureNavigation(title: "Remote", openDrawer: openDrawer) { RemoteView() }
        case .images: FeatureNavigation(title: "Images", openDrawer: openDrawer) { ImagesView { select(.chat) } }
        case .health: FeatureNavigation(title: "Health", openDrawer: openDrawer) { HealthView() }
        case .settings: NavigationStack { SettingsView().toolbar { drawerToolbar } }
        }
    }

    @ToolbarContentBuilder private var drawerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { Button(action: openDrawer) { Image(systemName: "line.3.horizontal") }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Open navigation") }
    }
    private func openDrawer() { isDrawerOpen = true }
    private func closeDrawer() { isDrawerOpen = false }
    private func select(_ value: AppDestination) { destination = value; closeDrawer() }
}

private struct FeatureNavigation<Content: View>: View {
    let title: String; let openDrawer: () -> Void; let content: Content
    init(title: String, openDrawer: @escaping () -> Void, @ViewBuilder content: () -> Content) { self.title = title; self.openDrawer = openDrawer; self.content = content() }
    var body: some View { NavigationStack { content.navigationTitle(title).toolbar { ToolbarItem(placement: .topBarLeading) { Button(action: openDrawer) { Image(systemName: "line.3.horizontal") }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Open navigation") } } } }
}
