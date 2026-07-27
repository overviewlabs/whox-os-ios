import SwiftUI

struct NavigationDrawer: View {
    @Environment(AppModel.self) private var model

    let onSelect: (AppDestination) -> Void

    private let menuItems: [DrawerItem] = [
        .init(title: "Library", icon: "books.vertical", destination: .activity),
        .init(title: "Projects", icon: "folder", destination: .control),
        .init(title: "Scheduled", icon: "clock", destination: .activity),
        .init(title: "Plugins", icon: "point.3.connected.trianglepath.dotted", destination: .control),
        .init(title: "Remote", icon: "desktopcomputer", destination: .settings),
        .init(title: "More", icon: "ellipsis", destination: .settings)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            primaryNavigation
            recents
            Spacer(minLength: 12)
            accountBar
        }
        .padding(.horizontal, 22)
        .padding(.top, -7)
        .padding(.bottom, 10)
        .background(WHOXTheme.background)
    }

    private var header: some View {
        HStack {
            Text("WHOX OS")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WHOXTheme.primaryText)

            Spacer()

            Button(action: {}) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(WHOXTheme.primaryText)
                    .frame(width: 42, height: 42)
                    .background(WHOXTheme.surface, in: Circle())
                    .overlay { Circle().stroke(WHOXTheme.border, lineWidth: 1) }
            }
            .accessibilityLabel("Search")
        }
        .padding(.bottom, 13)
    }

    private var primaryNavigation: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(menuItems) { item in
                Button {
                    onSelect(item.destination)
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .regular))
                            .frame(width: 22)
                        Text(item.title)
                            .font(.system(size: 15, weight: .regular))
                    }
                    .foregroundStyle(WHOXTheme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 33, alignment: .leading)
                }
            }
        }
        .padding(.bottom, 26)
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recents")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WHOXTheme.primaryText)
                .padding(.bottom, 13)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    recentButton(title: "New chat", sessionID: nil)

                    ForEach(model.sessions) { session in
                        recentButton(title: session.title ?? "Untitled", sessionID: session.id)
                    }
                }
            }
        }
    }

    private var accountBar: some View {
        HStack {
            Button {
                onSelect(.chat)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "square.and.pencil")
                    Text("Chat")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .frame(height: 40)
                .background(Color(red: 0.0, green: 0.55, blue: 0.95), in: Capsule())
            }

            Spacer()

            Button {
                onSelect(.settings)
            } label: {
                Text("EO")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WHOXTheme.primaryText)
                    .frame(width: 30, height: 30)
                    .background(WHOXTheme.avatarSurface, in: Circle())
                    .overlay { Circle().stroke(WHOXTheme.border, lineWidth: 1) }
            }
            .accessibilityLabel("Account settings")
        }
        .padding(.leading, 10)
    }

    private func recentButton(title: String, sessionID: String?) -> some View {
        Button {
            model.selectedSessionID = sessionID
            onSelect(.chat)
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(WHOXTheme.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        }
    }
}

private struct DrawerItem: Identifiable {
    let title: String
    let icon: String
    let destination: AppDestination

    var id: String { title }
}
