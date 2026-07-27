import SwiftUI
import WHOXCore

struct NavigationDrawer: View {
    @Environment(AppModel.self) private var model
    let onSelect: (AppDestination) -> Void
    @State private var query = ""
    @State private var renameSession: WHOXSession?
    @State private var renameText = ""

    private let items: [(String, String, AppDestination)] = [
        ("Library", "books.vertical", .library), ("Projects", "folder", .projects),
        ("Scheduled", "clock", .scheduled), ("Plugins", "puzzlepiece.extension", .plugins),
        ("Remote", "desktopcomputer", .remote), ("Images", "photo.on.rectangle.angled", .images),
        ("Health", "heart.text.square", .health)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("WHOX").font(.title3.bold()); Spacer(); Button { model.newChat(); onSelect(.chat) } label: { Image(systemName: "square.and.pencil").frame(width: 44, height: 44) }.accessibilityLabel("New chat") }
            searchField.padding(.bottom, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items, id: \.0) { item in drawerButton(item.0, icon: item.1) { onSelect(item.2) } }
                    Divider().padding(.vertical, 12)
                    sessionSections
                }
            }
            Divider()
            Button { onSelect(.settings) } label: {
                HStack(spacing: 12) {
                    Image("WHOXStudioLogo").resizable().scaledToFit().frame(width: 36, height: 36).clipShape(Circle())
                    VStack(alignment: .leading) { Text(model.authenticatedUser?.email ?? "WHOX member").font(.subheadline.weight(.semibold)).lineLimit(1); Text("Settings").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); Image(systemName: "ellipsis")
                }.foregroundStyle(.primary).frame(minHeight: 58)
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea())
        .alert("Rename chat", isPresented: Binding(get: { renameSession != nil }, set: { if !$0 { renameSession = nil } })) {
            TextField("Chat title", text: $renameText)
            Button("Cancel", role: .cancel) { renameSession = nil }
            Button("Rename") { if let id = renameSession?.id { Task { await model.renameSession(id, title: renameText) } }; renameSession = nil }
        }
    }

    private var searchField: some View { HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search chats", text: $query).textInputAutocapitalization(.never); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } } }.padding(.horizontal, 12).frame(minHeight: 44).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12)) }

    @ViewBuilder private var sessionSections: some View {
        let filtered = model.sessions.filter { query.isEmpty || ($0.title ?? $0.preview ?? "").localizedCaseInsensitiveContains(query) }
        let pinned = filtered.filter { model.pinnedSessionIDs.contains($0.id) }
        if !pinned.isEmpty { section("Pinned", sessions: pinned) }
        ForEach(grouped(filtered.filter { !model.pinnedSessionIDs.contains($0.id) })) { group in section(group.title, sessions: group.sessions) }
        if filtered.isEmpty { Text(model.isLoading ? "Loading chats…" : "No chats found").font(.subheadline).foregroundStyle(.secondary).padding(12) }
    }

    private func section(_ title: String, sessions: [WHOXSession]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 8)
            ForEach(sessions) { session in
                Button { Task { await model.selectSession(session.id); onSelect(.chat) } } label: { Text(session.title ?? session.preview ?? "Untitled chat").font(.subheadline).lineLimit(1).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading).padding(.horizontal, 10).contentShape(Rectangle()) }.buttonStyle(.plain)
                    .contextMenu {
                        Button(model.pinnedSessionIDs.contains(session.id) ? "Unpin" : "Pin", systemImage: "pin") { model.togglePin(session.id) }
                        Button("Rename", systemImage: "pencil") { renameText = session.title ?? ""; renameSession = session }
                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.deleteSession(session.id) } }
                    }
            }
        }
    }
    private func drawerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View { Button(action: action) { Label(title, systemImage: icon).font(.body).frame(maxWidth: .infinity, minHeight: 42, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).padding(.horizontal, 8) }
    private func grouped(_ sessions: [WHOXSession]) -> [SessionGroup] {
        var result: [SessionGroup] = []; let calendar = Calendar.current; let now = Date()
        for title in ["Today", "Yesterday", "Previous 7 days", "Earlier"] {
            let values = sessions.filter { s in let date = Date(timeIntervalSince1970: s.activityTimestamp); switch title { case "Today": return calendar.isDateInToday(date); case "Yesterday": return calendar.isDateInYesterday(date); case "Previous 7 days": return !calendar.isDateInToday(date) && !calendar.isDateInYesterday(date) && date > calendar.date(byAdding: .day, value: -7, to: now)!; default: return date <= calendar.date(byAdding: .day, value: -7, to: now)! } }
            if !values.isEmpty { result.append(SessionGroup(title: title, sessions: values)) }
        }; return result
    }
}

private struct SessionGroup: Identifiable {
    let title: String
    let sessions: [WHOXSession]
    var id: String { title }
}
