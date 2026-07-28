import SwiftUI
import WHOXCore

struct NavigationDrawer: View {
    @Environment(AppModel.self) private var model
    let onSelect: (AppDestination) -> Void

    @State private var query = ""
    @State private var showsSearch = false
    @State private var showsMore = false
    @State private var renameSession: WHOXSession?
    @State private var renameText = ""

    private let primaryItems: [(String, String, AppDestination)] = [
        ("Library", "books.vertical", .library),
        ("Projects", "folder", .projects),
        ("Scheduled", "clock", .scheduled),
        ("Plugins", "puzzlepiece.extension", .plugins),
        ("Remote", "desktopcomputer", .remote),
    ]

    private let moreItems: [(String, String, AppDestination)] = [
        ("Images", "photo.on.rectangle.angled", .images),
        ("Health", "heart.text.square", .health),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            if showsSearch {
                searchField
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(primaryItems, id: \.0) { item in
                        drawerButton(item.0, icon: item.1) { onSelect(item.2) }
                    }
                    drawerButton("More", icon: "ellipsis") {
                        withAnimation(.snappy(duration: 0.22)) { showsMore.toggle() }
                    }
                    if showsMore {
                        ForEach(moreItems, id: \.0) { item in
                            drawerButton(item.0, icon: item.1) { onSelect(item.2) }
                                .padding(.leading, 18)
                        }
                    }

                    sessionSections
                        .padding(.top, 28)
                }
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            bottomBar
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(WHOXTheme.background.ignoresSafeArea())
        .alert(
            "Rename chat",
            isPresented: Binding(
                get: { renameSession != nil },
                set: { if !$0 { renameSession = nil } }
            )
        ) {
            TextField("Chat title", text: $renameText)
            Button("Cancel", role: .cancel) { renameSession = nil }
            Button("Rename") {
                if let id = renameSession?.id {
                    Task { await model.renameSession(id, title: renameText) }
                }
                renameSession = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("WHOX OS")
                .font(.system(size: 25, weight: .semibold))
            Spacer()
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    showsSearch.toggle()
                    if !showsSearch { query = "" }
                }
            } label: {
                Image(systemName: showsSearch ? "xmark" : "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 46, height: 46)
                    .background(Color.primary.opacity(0.08), in: Circle())
                    .overlay { Circle().stroke(WHOXTheme.border, lineWidth: 0.7) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsSearch ? "Close chat search" : "Search chats")
        }
        .frame(minHeight: 50)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search chats", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear chat search")
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 44)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    @ViewBuilder private var sessionSections: some View {
        let filtered = model.sessions.filter {
            query.isEmpty || ($0.title ?? $0.preview ?? "").localizedCaseInsensitiveContains(query)
        }
        let pinned = filtered.filter { model.pinnedSessionIDs.contains($0.id) }
        let recents = filtered.filter { !model.pinnedSessionIDs.contains($0.id) }

        if !pinned.isEmpty { section("Pinned", sessions: pinned) }
        if !recents.isEmpty { section("Recents", sessions: recents) }
        if filtered.isEmpty {
            Text(model.isLoading ? "Loading chats…" : "No chats found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
        }
    }

    private func section(_ title: String, sessions: [WHOXSession]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 10)
            ForEach(sessions) { session in
                Button {
                    Task {
                        await model.selectSession(session.id)
                        onSelect(.chat)
                    }
                } label: {
                    Text(session.title ?? session.preview ?? "Untitled chat")
                        .font(.body)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(model.pinnedSessionIDs.contains(session.id) ? "Unpin" : "Pin", systemImage: "pin") {
                        model.togglePin(session.id)
                    }
                    Button("Rename", systemImage: "pencil") {
                        renameText = session.title ?? ""
                        renameSession = session
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await model.deleteSession(session.id) }
                    }
                }
            }
        }
        .padding(.bottom, 22)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                model.newChat()
                onSelect(.chat)
            } label: {
                Label("Chat", systemImage: "square.and.pencil")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 48)
                    .background(WHOXTheme.action, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New chat")

            Spacer()

            Button { onSelect(.settings) } label: {
                Image("WHOXStudioLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .padding(3)
                    .background(Color.primary.opacity(0.09), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open settings for \(model.authenticatedUser?.email ?? "WHOX member")")
        }
        .padding(.top, 8)
    }

    private func drawerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 17))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
