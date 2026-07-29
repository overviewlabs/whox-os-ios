import SwiftUI
import UIKit
import WHOXCore

enum AppDestination: Hashable {
    case chat, library, projects, scheduled, plugins, remote, images, health, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var destination: AppDestination = .chat
    @State private var openPanel: DrawerSide?
    @State private var dragSide: DrawerSide?
    @State private var dragTranslation: CGFloat = 0
    @State private var showDebugControls = false

    init() {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--visual-review-settings") {
            _destination = State(initialValue: .settings)
        }
        if arguments.contains("--visual-review-navigation") {
            _openPanel = State(initialValue: .leading)
        }
        if arguments.contains("--visual-review-directory") {
            _openPanel = State(initialValue: .trailing)
        }
#endif
    }

    private var panelAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .interactiveSpring(response: 0.34, dampingFraction: 0.86)
    }

    var body: some View {
        Group {
            switch model.authenticationState {
            case .checking:
                ZStack { WHOXTheme.background.ignoresSafeArea(); ProgressView() }
            case .signedOut:
                LoginView()
            case .signedIn:
                authenticatedContent
            }
        }
        .tint(WHOXTheme.action)
        .task { await model.restoreAuthenticationIfNeeded() }
    }

    private var authenticatedContent: some View {
        GeometryReader { geometry in
            let navigationWidth = DrawerPresentationContract.width(containerWidth: geometry.size.width)
            let directoryWidth = DrawerPresentationContract.width(containerWidth: geometry.size.width)
            let leadingProgress = panelProgress(.leading, width: navigationWidth)
            let trailingProgress = panelProgress(.trailing, width: directoryWidth)
            let panelProgress = max(leadingProgress, trailingProgress)
            let mainOffset = navigationWidth * leadingProgress - directoryWidth * trailingProgress

            ZStack {
                HStack(spacing: 0) {
                    NavigationDrawer(onSelect: select, onClose: closePanels)
                        .frame(width: navigationWidth)
                        .frame(maxHeight: .infinity)
                        .opacity(DrawerPresentationContract.opacity(progress: leadingProgress))
                        .allowsHitTesting(leadingProgress > 0.01)
                        .accessibilityHidden(leadingProgress == 0)
                        .accessibilityAddTraits(.isModal)
                    Spacer(minLength: 0)
                }

                if DrawerAccessContract.canOpen(.trailing, role: model.authenticatedUser?.role) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        DirectoryDrawer(model: model, onClose: closePanels)
                            .frame(width: directoryWidth)
                            .frame(maxHeight: .infinity)
                            .opacity(DrawerPresentationContract.opacity(progress: trailingProgress))
                            .allowsHitTesting(trailingProgress > 0.01)
                            .accessibilityHidden(trailingProgress == 0)
                            .accessibilityAddTraits(.isModal)
                    }
                }

                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if panelProgress > 0 {
                            Color.primary.opacity(DrawerPresentationContract.scrimOpacity(progress: panelProgress))
                                .contentShape(Rectangle())
                                .onTapGesture { closePanels() }
                                .accessibilityLabel("Close side panel")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: leadingProgress * 42,
                        bottomLeadingRadius: leadingProgress * 42,
                        bottomTrailingRadius: trailingProgress * 42,
                        topTrailingRadius: trailingProgress * 42,
                        style: .continuous
                    ))
                    .shadow(color: .black.opacity(0.3 * panelProgress), radius: 24, x: mainOffset > 0 ? -8 : 8)
                    .offset(x: mainOffset)
                    .accessibilityHidden(panelProgress > 0)
            }
            .background(WHOXTheme.background.ignoresSafeArea())
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(panelDrag(
                containerWidth: geometry.size.width,
                leadingWidth: navigationWidth,
                trailingWidth: directoryWidth
            ))
        }
        .background(WHOXTheme.background.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: .whoxDebugToggleDrawer)) { _ in
#if DEBUG
            if openPanel == .leading { closePanels() } else { open(.leading) }
#endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .whoxDebugToggleDirectory)) { _ in
#if DEBUG
            if openPanel == .trailing { closePanels() } else { openDirectory() }
#endif
        }
        .onReceive(NotificationCenter.default.publisher(for: .whoxDebugShowControls)) { note in
#if DEBUG
            showDebugControls = (note.object as? Bool) ?? true
#endif
        }
        .overlay(alignment: .bottomTrailing) {
#if DEBUG
            if showDebugControls { debugControls.padding(12) }
#endif
        }
    }

    @ViewBuilder private var mainContent: some View {
        switch destination {
        case .chat:
            ChatHomeView(onOpenDrawer: { open(.leading) }, onOpenDirectory: openDirectory)
        case .library:
            FeatureNavigation(title: "Library", openDrawer: { open(.leading) }) { LibraryView() }
        case .projects:
            FeatureNavigation(title: "Projects", openDrawer: { open(.leading) }) { ProjectsView() }
        case .scheduled:
            FeatureNavigation(title: "Scheduled", openDrawer: { open(.leading) }) { ScheduledView() }
        case .plugins:
            FeatureNavigation(title: "Plugins", openDrawer: { open(.leading) }) { PluginsView() }
        case .remote:
            FeatureNavigation(title: "Remote", openDrawer: { open(.leading) }) { RemoteView() }
        case .images:
            FeatureNavigation(title: "Images", openDrawer: { open(.leading) }) { ImagesView { select(.chat) } }
        case .health:
            FeatureNavigation(title: "Health", openDrawer: { open(.leading) }) { HealthView() }
        case .settings:
            NavigationStack { SettingsView().toolbar { drawerToolbar } }
        }
    }

    @ToolbarContentBuilder private var drawerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { open(.leading) } label: { Image(systemName: "line.3.horizontal") }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Open navigation")
        }
    }

    private func select(_ value: AppDestination) {
        dismissKeyboard()
        destination = value
        closePanels()
    }

    private func panelProgress(_ side: DrawerSide, width: CGFloat) -> CGFloat {
        if openPanel == side {
            guard dragSide == side else { return 1 }
            switch side {
            case .leading: return min(1, max(0, 1 + dragTranslation / width))
            case .trailing: return min(1, max(0, 1 - dragTranslation / width))
            }
        }
        guard openPanel == nil, dragSide == side else { return 0 }
        switch side {
        case .leading: return min(1, max(0, dragTranslation / width))
        case .trailing: return min(1, max(0, -dragTranslation / width))
        }
    }

    private func panelDrag(containerWidth: CGFloat, leadingWidth: CGFloat, trailingWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if dragSide == nil {
                    let candidate = openPanel ?? DrawerGestureContract.openingSide(
                        startX: value.startLocation.x,
                        containerWidth: containerWidth
                    )
                    dragSide = candidate.flatMap {
                        DrawerAccessContract.canOpen($0, role: model.authenticatedUser?.role) ? $0 : nil
                    }
                    if dragSide != nil { dismissKeyboard() }
                }
                guard let side = dragSide else { return }
                switch (side, openPanel) {
                case (.leading, .leading):
                    dragTranslation = min(0, max(-leadingWidth, value.translation.width))
                case (.leading, nil):
                    dragTranslation = max(0, min(leadingWidth, value.translation.width))
                case (.trailing, .trailing):
                    dragTranslation = max(0, min(trailingWidth, value.translation.width))
                case (.trailing, nil):
                    dragTranslation = min(0, max(-trailingWidth, value.translation.width))
                default:
                    break
                }
            }
            .onEnded { value in
                guard let side = dragSide else { return }
                let width = side == .leading ? leadingWidth : trailingWidth
                let predicted = value.predictedEndTranslation.width
                let committed = DrawerGestureContract.shouldCommit(
                    translation: value.translation.width,
                    predictedTranslation: predicted,
                    width: width
                )
                let wasOpen = openPanel == side
                let directionMatches: Bool
                switch (side, wasOpen) {
                case (.leading, false): directionMatches = predicted > 0
                case (.leading, true): directionMatches = predicted < 0
                case (.trailing, false): directionMatches = predicted < 0
                case (.trailing, true): directionMatches = predicted > 0
                }
                withAnimation(panelAnimation) {
                    if committed && directionMatches {
                        openPanel = wasOpen ? nil : side
                        if side == .trailing, !wasOpen {
                            Task { await model.loadDirectory(model.directoryListing?.path ?? "") }
                        }
                    }
                    dragSide = nil
                    dragTranslation = 0
                }
            }
    }

    private func open(_ side: DrawerSide) {
        guard DrawerAccessContract.canOpen(side, role: model.authenticatedUser?.role) else { return }
        dismissKeyboard()
        withAnimation(panelAnimation) {
            dragSide = nil
            dragTranslation = 0
            openPanel = side
        }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func openDirectory() {
        open(.trailing)
        guard openPanel == .trailing else { return }
        Task { await model.loadDirectory(model.directoryListing?.path ?? "") }
    }

    private func closePanels() {
        withAnimation(panelAnimation) {
            dragSide = nil
            dragTranslation = 0
            openPanel = nil
        }
    }

#if DEBUG
    private var debugControls: some View {
        HStack(spacing: 8) {
            Button("Menu") { open(.leading) }
            if model.authenticatedUser?.role == "owner" {
                Button("Files") { openDirectory() }
            }
            Button("Close") { closePanels() }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .accessibilityIdentifier("debug-drawer-controls")
    }
#endif
}

private struct FeatureNavigation<Content: View>: View {
    let title: String
    let openDrawer: () -> Void
    let content: Content

    init(title: String, openDrawer: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.openDrawer = openDrawer
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: openDrawer) { Image(systemName: "line.3.horizontal") }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Open navigation")
                    }
                }
        }
    }
}

private extension Notification.Name {
    static let whoxDebugToggleDrawer = Notification.Name("WHOXDebugToggleDrawer")
    static let whoxDebugToggleDirectory = Notification.Name("WHOXDebugToggleDirectory")
    static let whoxDebugShowControls = Notification.Name("WHOXDebugShowControls")
}
