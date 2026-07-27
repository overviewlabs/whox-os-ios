import SwiftUI

enum AppDestination: Hashable {
    case chat
    case activity
    case control
    case settings
}

struct RootView: View {
    @State private var destination: AppDestination = .chat
    @State private var isDrawerOpen = false

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = geometry.size.width * 0.74

            ZStack(alignment: .leading) {
                WHOXTheme.background.ignoresSafeArea()

                mainContent
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(WHOXTheme.background)
                    .offset(x: isDrawerOpen ? drawerWidth : 0)
                    .allowsHitTesting(!isDrawerOpen)

                if isDrawerOpen {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 30,
                        bottomLeadingRadius: 30,
                        style: .continuous
                    )
                    .fill(WHOXTheme.drawerOverlay)
                    .frame(width: geometry.size.width)
                    .offset(x: drawerWidth)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }

                NavigationDrawer(onSelect: select)
                .frame(width: drawerWidth)
                .offset(x: isDrawerOpen ? 0 : -drawerWidth)

                if isDrawerOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geometry.size.width - drawerWidth)
                        .offset(x: drawerWidth)
                        .onTapGesture(perform: closeDrawer)
                }
            }
            .animation(.snappy(duration: 0.3), value: isDrawerOpen)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch destination {
        case .chat:
            ChatHomeView(onOpenDrawer: openDrawer)
        case .activity:
            NavigationStack { ActivityView() }
        case .control:
            NavigationStack { ControlCenterView() }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }

    private func openDrawer() {
        isDrawerOpen = true
    }

    private func closeDrawer() {
        isDrawerOpen = false
    }

    private func select(_ newDestination: AppDestination) {
        destination = newDestination
        closeDrawer()
    }
}
