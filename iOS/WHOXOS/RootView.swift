import SwiftUI

enum AppDestination: Hashable { case chat, library, projects, scheduled, plugins, remote, images, health, settings }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var destination: AppDestination = .chat
    @State private var isDrawerOpen = false
    @State private var isDirectoryDrawerOpen = false

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--visual-review-settings") {
            _destination = State(initialValue: .settings)
        }
        if ProcessInfo.processInfo.arguments.contains("--visual-review-directory") {
            _isDirectoryDrawerOpen = State(initialValue: true)
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
        .tint(WHOXTheme.action)
        .task { await model.restoreAuthenticationIfNeeded() }
    }

    private var authenticatedContent: some View {
        GeometryReader { proxy in
            let navigationWidth = min(proxy.size.width * 0.78, 360)
            let directoryWidth = min(proxy.size.width * 0.88, 410)
            ZStack {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(isDrawerOpen || isDirectoryDrawerOpen)
                if isDrawerOpen || isDirectoryDrawerOpen {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .onTapGesture { closeDrawers() }
                        .transition(.opacity)
                }
                if isDrawerOpen {
                    HStack(spacing: 0) {
                        NavigationDrawer(onSelect: select)
                            .frame(width: navigationWidth)
                            .shadow(color: .black.opacity(0.2), radius: 18, x: 8)
                        Spacer(minLength: 0)
                    }
                    .transition(.move(edge: .leading))
                }
                if isDirectoryDrawerOpen {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        DirectoryDrawer(onClose: closeDirectoryDrawer)
                            .frame(width: directoryWidth)
                            .shadow(color: .black.opacity(0.22), radius: 20, x: -8)
                    }
                    .transition(.move(edge: .trailing))
                }
            }
            .animation(.snappy(duration: 0.28), value: isDrawerOpen)
            .animation(.snappy(duration: 0.28), value: isDirectoryDrawerOpen)
        }
    }

    @ViewBuilder private var mainContent: some View {
        switch destination {
        case .chat: ChatHomeView(onOpenDrawer: openDrawer, onOpenDirectory: openDirectoryDrawer)
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
    private func openDrawer() { isDirectoryDrawerOpen = false; isDrawerOpen = true }
    private func openDirectoryDrawer() { isDrawerOpen = false; isDirectoryDrawerOpen = true }
    private func closeDrawer() { isDrawerOpen = false }
    private func closeDirectoryDrawer() { isDirectoryDrawerOpen = false }
    private func closeDrawers() { isDrawerOpen = false; isDirectoryDrawerOpen = false }
    private func select(_ value: AppDestination) { destination = value; closeDrawers() }
}

private struct FeatureNavigation<Content: View>: View {
    let title: String; let openDrawer: () -> Void; let content: Content
    init(title: String, openDrawer: @escaping () -> Void, @ViewBuilder content: () -> Content) { self.title = title; self.openDrawer = openDrawer; self.content = content() }
    var body: some View { NavigationStack { content.navigationTitle(title).toolbar { ToolbarItem(placement: .topBarLeading) { Button(action: openDrawer) { Image(systemName: "line.3.horizontal") }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Open navigation") } } } }
}
