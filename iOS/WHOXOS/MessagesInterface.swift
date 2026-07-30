import Observation
import SwiftUI
import WHOXCore

struct ChatMessage: Identifiable, Hashable, Codable {
    enum Sender: String, Hashable, Codable {
        case contact
        case user
    }

    let id: String
    let sender: Sender
    let text: String
    let timestamp: Date

    init(id: String = UUID().uuidString.lowercased(), sender: Sender, text: String, timestamp: Date = .now) {
        self.id = id
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
    }
}

struct Conversation: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var initials: String
    var preview: String
    var timestamp: String
    var messages: [ChatMessage]
    var isMuted: Bool
    var isPinned: Bool
    var isUnread: Bool
    var model: String?
    var source: String?
    var activityTimestamp: Double?

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        initials: String,
        preview: String,
        timestamp: String = "7:13 PM",
        messages: [ChatMessage] = [],
        isMuted: Bool = false,
        isPinned: Bool = false,
        isUnread: Bool = false,
        model: String? = nil,
        source: String? = nil,
        activityTimestamp: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.initials = initials
        self.preview = preview
        self.timestamp = timestamp
        self.messages = messages
        self.isMuted = isMuted
        self.isPinned = isPinned
        self.isUnread = isUnread
        self.model = model
        self.source = source
        self.activityTimestamp = activityTimestamp
    }
}

@MainActor
@Observable
final class MessageStore {
    private static let lastReadAssistantIDsKey = "hermes.sessions.last-read-assistant-ids"
    private static let snapshotVersion = 2

    var conversations: [Conversation] {
        didSet { persistSnapshot() }
    }
    private(set) var hasCachedSnapshot: Bool
    var isSyncing = false
    private(set) var isLoadingSessions = false
    var sendingSessionIDs: Set<String> = []
    private(set) var loadingSessionIDs: Set<String> = []
    var errorMessage: String?
    @ObservationIgnored private var gatewayClient: HermesGatewayClient?
    @ObservationIgnored private var activeConversationID: Conversation.ID?
    @ObservationIgnored private var syncInProgress = false
    @ObservationIgnored private var connectionGeneration = 0
    @ObservationIgnored private var loadingSessionTokens: [Conversation.ID: UUID] = [:]
    @ObservationIgnored private var pendingReadActivityBaselineSessionIDs: Set<Conversation.ID> = []
    @ObservationIgnored private var lastReadAssistantIDs =
        UserDefaults.standard.dictionary(forKey: MessageStore.lastReadAssistantIDsKey)
            as? [String: String] ?? [:]

    init() {
        Self.deleteLegacySnapshot()
        if let snapshot = Self.loadSnapshot() {
            conversations = snapshot.conversations
            hasCachedSnapshot = true
        } else {
            conversations = []
            hasCachedSnapshot = false
        }
    }

    func conversation(_ id: Conversation.ID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func connect(
        to client: HermesGatewayClient,
        trigger: GatewaySyncTrigger = .manualConnection
    ) async throws {
        let startedGeneration = connectionGeneration
        while syncInProgress {
            guard trigger == .manualConnection else { return }
            try await Task.sleep(for: .milliseconds(100))
            try ensureCurrentGeneration(startedGeneration)
        }
        try ensureCurrentGeneration(startedGeneration)
        gatewayClient = client
        syncInProgress = true
        isLoadingSessions = true
        isSyncing = GatewaySyncPolicy.presentation(
            for: trigger,
            hasCachedSnapshot: hasCachedSnapshot
        ) == .blocking
        errorMessage = nil
        defer {
            isSyncing = false
            isLoadingSessions = false
            syncInProgress = false
        }

        let sessions = try await client.listAllSessions()
        try ensureCurrentConnection(startedGeneration)

        let loadPlan = GatewaySessionLoadPlan.indexRefresh(
            sessionIDs: sessions.map(\.id)
        )
        let existingByID = Dictionary(
            uniqueKeysWithValues: conversations.map { ($0.id, $0) }
        )
        var deferred: [HermesSession] = []
        var imported: [Conversation] = []
        imported.reserveCapacity(loadPlan.sessionIDs.count)
        for session in sessions {
            let existing = existingByID[session.id]
            if existing == nil,
               (GatewaySyncPolicy.shouldInspectPotentialHelper(
                   source: session.source,
                   isKnownSession: false
               ) || session.parentSessionID != nil) {
                deferred.append(session)
                continue
            }

            var conversation = Conversation(
                hermesSession: session,
                hermesMessages: []
            )
            if let existing {
                let consumesReadBaseline = pendingReadActivityBaselineSessionIDs.remove(session.id) != nil
                conversation.messages = existing.messages
                conversation.isMuted = existing.isMuted
                conversation.isPinned = existing.isPinned
                conversation.isUnread = GatewaySyncPolicy.isUnread(
                    previousActivity: existing.activityTimestamp,
                    currentActivity: session.activityTimestamp,
                    isActive: activeConversationID == session.id,
                    wasUnread: existing.isUnread,
                    consumesReadBaseline: consumesReadBaseline
                )
            }
            imported.append(conversation)
        }
        try ensureCurrentConnection(startedGeneration)

        hasCachedSnapshot = true
        conversations = imported

        guard !deferred.isEmpty else { return }
        var hydratedByID: [String: [HermesMessage]] = [:]
        var directLeakedSessionIDs: Set<String> = []
        var unresolvedSessionIDs: Set<String> = []
        for session in deferred where session.source == "api_server" {
            do {
                let messages = try await client.messages(sessionID: session.id)
                try ensureCurrentConnection(startedGeneration)
                hydratedByID[session.id] = messages
                if Self.isLeakedTitleHelperSession(messages) {
                    directLeakedSessionIDs.insert(session.id)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep unclassified sessions hidden and retry on the next index refresh.
                unresolvedSessionIDs.insert(session.id)
            }
        }

        let parentBySessionID = Dictionary(
            uniqueKeysWithValues: sessions.compactMap { session in
                session.parentSessionID.map { (session.id, $0) }
            }
        )
        let leakedSessionIDs = GatewaySyncPolicy.descendants(
            of: directLeakedSessionIDs,
            parentBySessionID: parentBySessionID
        )
        unresolvedSessionIDs = GatewaySyncPolicy.descendants(
            of: unresolvedSessionIDs,
            parentBySessionID: parentBySessionID
        )

        for session in deferred {
            guard
                !leakedSessionIDs.contains(session.id),
                !unresolvedSessionIDs.contains(session.id),
                GatewaySyncPolicy.canImportPotentialHelper(
                    source: session.source,
                    inspectionSucceeded: hydratedByID[session.id] != nil
                )
            else {
                continue
            }
            let messages = hydratedByID[session.id] ?? []
            conversations.append(Conversation(
                hermesSession: session,
                hermesMessages: messages
            ))
            if let latestAssistantID = Self.latestAssistantID(in: messages) {
                lastReadAssistantIDs[session.id] = latestAssistantID
            }
        }
        conversations.sort { ($0.activityTimestamp ?? 0) > ($1.activityTimestamp ?? 0) }
        persistReadState()

        for sessionID in leakedSessionIDs {
            try ensureCurrentConnection(startedGeneration)
            try? await client.deleteSession(sessionID)
        }
        try ensureCurrentConnection(startedGeneration)
    }

    @discardableResult
    func refresh(trigger: GatewaySyncTrigger = .periodic) async -> Bool {
        guard let gatewayClient else { return false }
        guard sendingSessionIDs.isEmpty, loadingSessionIDs.isEmpty else { return true }
        do {
            try await connect(to: gatewayClient, trigger: trigger)
            return true
        } catch {
            if trigger == .manualConnection {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func loadMessages(for sessionID: Conversation.ID) async {
        guard let client = gatewayClient else { return }
        guard loadingSessionTokens[sessionID] == nil else { return }
        let startedGeneration = connectionGeneration
        let loadingToken = UUID()
        loadingSessionTokens[sessionID] = loadingToken
        loadingSessionIDs.insert(sessionID)
        defer {
            if loadingSessionTokens[sessionID] == loadingToken {
                loadingSessionTokens[sessionID] = nil
                loadingSessionIDs.remove(sessionID)
            }
        }

        do {
            while syncInProgress {
                try await Task.sleep(for: .milliseconds(50))
                try ensureCurrentConnection(startedGeneration)
            }
            let loadPlan = GatewaySessionLoadPlan.openSession(sessionID)
            guard loadPlan.messageSessionIDs == [sessionID] else { return }

            let messages = try await client.messages(sessionID: sessionID)
            try ensureCurrentConnection(startedGeneration)
            guard let index = conversations.firstIndex(where: { $0.id == sessionID }) else { return }

            let mapped = messages
                .filter {
                    ($0.role == "user" || $0.role == "assistant")
                        && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .map(ChatMessage.init(hermesMessage:))
            conversations[index].messages = mapped
            if let latest = mapped.last {
                conversations[index].preview = latest.text
                conversations[index].timestamp = Self.timeFormatter.string(from: latest.timestamp)
            }
            if let latestAssistantID = Self.latestAssistantID(in: messages) {
                if activeConversationID == sessionID {
                    lastReadAssistantIDs[sessionID] = latestAssistantID
                    conversations[index].isUnread = false
                } else if let lastReadID = lastReadAssistantIDs[sessionID] {
                    conversations[index].isUnread = lastReadID != latestAssistantID
                } else {
                    lastReadAssistantIDs[sessionID] = latestAssistantID
                }
                persistReadState()
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        connectionGeneration &+= 1
        gatewayClient = nil
        hasCachedSnapshot = false
        Self.deleteSnapshot()
        conversations = []
        isSyncing = false
        isLoadingSessions = false
        sendingSessionIDs = []
        loadingSessionTokens = [:]
        loadingSessionIDs = []
        pendingReadActivityBaselineSessionIDs = []
        errorMessage = nil
    }

    func send(_ text: String, to id: Conversation.ID) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !clean.isEmpty,
            !loadingSessionIDs.contains(id),
            let index = conversations.firstIndex(where: { $0.id == id })
        else {
            return
        }
        conversations[index].messages.append(ChatMessage(sender: .user, text: clean))
        conversations[index].preview = clean
        conversations[index].timestamp = Self.timeFormatter.string(from: .now)
        conversations[index].isUnread = false
        let updated = conversations.remove(at: index)
        conversations.insert(updated, at: 0)

        guard let gatewayClient else { return }
        let startedGeneration = connectionGeneration
        sendingSessionIDs.insert(id)
        defer { sendingSessionIDs.remove(id) }
        do {
            let reply = try await gatewayClient.chat(sessionID: id, input: clean)
            try ensureCurrentConnection(startedGeneration)
            guard let currentIndex = conversations.firstIndex(where: { $0.id == id }) else { return }
            let message = ChatMessage(hermesMessage: reply)
            conversations[currentIndex].messages.append(message)
            conversations[currentIndex].preview = message.text
            conversations[currentIndex].timestamp = Self.timeFormatter.string(from: message.timestamp)
            if activeConversationID == id {
                markLatestAssistantRead(in: id)
                pendingReadActivityBaselineSessionIDs.insert(id)
                if let session = try? await gatewayClient.session(id) {
                    try ensureCurrentConnection(startedGeneration)
                    guard let refreshedIndex = conversations.firstIndex(where: { $0.id == id }) else { return }
                    conversations[refreshedIndex].activityTimestamp = session.activityTimestamp
                    pendingReadActivityBaselineSessionIDs.remove(id)
                }
            } else {
                conversations[currentIndex].isUnread = true
            }
            Task { await refreshHermesGeneratedTitle(for: id) }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createConversation(recipient: String) async -> Conversation.ID? {
        let clean = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if let gatewayClient {
            do {
                let session = try await gatewayClient.createSession()
                var conversation = Conversation(hermesSession: session, hermesMessages: [])
                if session.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    conversation.name = clean
                    conversation.initials = Conversation.initials(for: clean)
                }
                conversations.insert(conversation, at: 0)
                return conversation.id
            } catch {
                errorMessage = error.localizedDescription
                return nil
            }
        }
        let words = clean.split(separator: " ")
        let initials = words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        let conversation = Conversation(
            name: clean,
            initials: initials.isEmpty ? "—" : initials,
            preview: "New conversation",
            timestamp: "Now"
        )
        conversations.insert(conversation, at: 0)
        return conversation.id
    }

    func delete(at offsets: IndexSet, from visible: [Conversation]) {
        let ids = Set(offsets.map { visible[$0].id })
        conversations.removeAll { ids.contains($0.id) }
    }

    func delete(_ id: Conversation.ID) {
        conversations.removeAll { $0.id == id }
        guard let gatewayClient else { return }
        Task {
            do {
                try await gatewayClient.deleteSession(id)
            } catch {
                errorMessage = error.localizedDescription
                await refresh()
            }
        }
    }

    func toggleMuted(_ id: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isMuted.toggle()
    }

    func togglePinned(_ id: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isPinned.toggle()
        conversations.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return false
        }
    }

    func markUnread(_ id: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isUnread = true
    }

    func openConversation(_ id: Conversation.ID) {
        activeConversationID = id
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isUnread = false
        markLatestAssistantRead(in: id)
    }

    func closeConversation(_ id: Conversation.ID) {
        guard activeConversationID == id else { return }
        activeConversationID = nil
    }

    private func refreshHermesGeneratedTitle(for id: Conversation.ID) async {
        guard let gatewayClient else { return }
        for attempt in 0..<6 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(1))
            }
            guard
                let session = try? await gatewayClient.session(id),
                let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty
            else {
                continue
            }
            guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
            withAnimation(.whoxSmooth) {
                conversations[index].name = title
                conversations[index].initials = Conversation.initials(for: title)
                conversations[index].model = session.model
                conversations[index].source = session.source
            }
            return
        }
    }

    private static func isLeakedTitleHelperSession(_ messages: [HermesMessage]) -> Bool {
        let content = messages.map(\.content).joined(separator: "\n")
        return content.contains("CURRENT TITLE:")
            && content.contains("ESTABLISHED CONVERSATION:")
            && content.contains("THREE MOST RECENT EXCHANGES:")
    }

    private static func latestAssistantID(in messages: [HermesMessage]) -> String? {
        messages.last {
            $0.role == "assistant"
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.id
    }

    private func markLatestAssistantRead(in id: Conversation.ID) {
        guard
            let conversation = conversations.first(where: { $0.id == id }),
            let latestAssistantID = conversation.messages.last(where: { $0.sender == .contact })?.id
        else {
            return
        }
        lastReadAssistantIDs[id] = latestAssistantID
        persistReadState()
    }

    private func persistReadState() {
        UserDefaults.standard.set(lastReadAssistantIDs, forKey: Self.lastReadAssistantIDsKey)
    }

    private func ensureCurrentGeneration(_ startedGeneration: Int) throws {
        try Task.checkCancellation()
        guard GatewaySyncPolicy.canCommit(
            startedGeneration: startedGeneration,
            currentGeneration: connectionGeneration
        ) else {
            throw CancellationError()
        }
    }

    private func ensureCurrentConnection(_ startedGeneration: Int) throws {
        try ensureCurrentGeneration(startedGeneration)
        guard gatewayClient != nil else {
            throw CancellationError()
        }
    }

    private struct StoredSnapshot: Codable {
        let version: Int
        let savedAt: Date
        let conversations: [Conversation]
    }

    private static var snapshotURL: URL? {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return directory
            .appendingPathComponent("WHOXOS", isDirectory: true)
            .appendingPathComponent("hermes-sessions-v2.json", isDirectory: false)
    }

    private static var legacySnapshotURL: URL? {
        snapshotURL?.deletingLastPathComponent()
            .appendingPathComponent("hermes-sessions.json", isDirectory: false)
    }

    private static func loadSnapshot() -> StoredSnapshot? {
        guard
            let url = snapshotURL,
            let data = try? Data(contentsOf: url),
            let snapshot = try? JSONDecoder().decode(StoredSnapshot.self, from: data),
            snapshot.version == snapshotVersion
        else {
            return nil
        }
        return snapshot
    }

    private func persistSnapshot() {
        guard hasCachedSnapshot, let url = Self.snapshotURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            let snapshot = StoredSnapshot(
                version: Self.snapshotVersion,
                savedAt: .now,
                conversations: conversations
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            // A cache failure must never interrupt live chat or disconnect the gateway.
        }
    }

    private static func deleteSnapshot() {
        guard let url = snapshotURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func deleteLegacySnapshot() {
        guard let url = legacySnapshotURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    fileprivate static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

@MainActor
private extension Conversation {
    init(hermesSession session: HermesSession, hermesMessages: [HermesMessage]) {
        let mappedMessages = hermesMessages
            .filter {
                ($0.role == "user" || $0.role == "assistant")
                    && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .map(ChatMessage.init(hermesMessage:))
        let displayName = session.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (displayName?.isEmpty == false ? displayName : nil)
            ?? session.model
            ?? "Hermes Agent"
        let preview = mappedMessages.last?.text
            ?? session.preview
            ?? "New conversation"
        let activityDate = session.activityTimestamp > 0
            ? Date(timeIntervalSince1970: session.activityTimestamp)
            : .now

        self.init(
            id: session.id,
            name: name,
            initials: Self.initials(for: name),
            preview: preview,
            timestamp: MessageStore.timeFormatter.string(from: activityDate),
            messages: mappedMessages,
            model: session.model,
            source: session.source,
            activityTimestamp: session.activityTimestamp
        )
    }

    static func initials(for name: String) -> String {
        let value = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        return value.isEmpty ? "HA" : value
    }
}

private extension ChatMessage {
    init(hermesMessage message: HermesMessage) {
        self.init(
            id: message.id,
            sender: message.role == "user" ? .user : .contact,
            text: message.content,
            timestamp: message.timestamp.map(Date.init(timeIntervalSince1970:)) ?? .now
        )
    }
}

struct MessagesListView: View {
    @Environment(MessageStore.self) private var store
    @Environment(GatewayConfiguration.self) private var gatewayConfiguration
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Conversation.ID] = []
    @State private var searchText = ""
    @State private var showingNewMessage = false
    @State private var showingGatewaySetup = false
    @State private var sessionScrollPosition: Conversation.ID?
    @FocusState private var searchFocused: Bool

    private var visibleConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.conversations }
        return store.conversations.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                $0.preview.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if visibleConversations.isEmpty && store.isLoadingSessions {
                    HStack {
                        Spacer()
                        ProgressView("Loading sessions…")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .padding(.top, 48)
                }
                ForEach(visibleConversations) { conversation in
                    VStack(spacing: 0) {
                        NavigationLink(value: conversation.id) {
                            ConversationRow(conversation: conversation)
                        }
                        .contextMenu {
                            Button {
                                withAnimation { store.togglePinned(conversation.id) }
                            } label: {
                                Label(
                                    conversation.isPinned ? "Unpin" : "Pin",
                                    systemImage: conversation.isPinned ? "pin.slash" : "pin"
                                )
                            }

                            Button {
                                withAnimation { store.markUnread(conversation.id) }
                            } label: {
                                Label("Mark as Unread", systemImage: "message.badge")
                            }

                            Button {
                                withAnimation { store.toggleMuted(conversation.id) }
                            } label: {
                                Label(
                                    conversation.isMuted ? "Show Alerts" : "Hide Alerts",
                                    systemImage: conversation.isMuted ? "bell" : "bell.slash"
                                )
                            }

                            Button(role: .destructive) {
                                withAnimation { store.delete(conversation.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } preview: {
                            ConversationContextPreview(conversation: conversation)
                        }
                        Divider()
                            .padding(.leading, 64)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        )
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 25, bottom: 0, trailing: 14))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            withAnimation { store.delete(conversation.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)

                        Button {
                            withAnimation { store.toggleMuted(conversation.id) }
                        } label: {
                            Label(
                                conversation.isMuted ? "Show Alerts" : "Hide Alerts",
                                systemImage: conversation.isMuted ? "bell" : "bell.slash.fill"
                            )
                        }
                        .tint(.indigo)
                    }
                }
                .onDelete { store.delete(at: $0, from: visibleConversations) }
            }
            .animation(.whoxSmooth, value: visibleConversations)
            .scrollPosition(id: $sessionScrollPosition, anchor: .top)
            .onChange(of: visibleConversations.first?.id) { _, newestID in
                guard let newestID else { return }
                withAnimation(.whoxSmooth) {
                    sessionScrollPosition = newestID
                }
            }
            .listStyle(.plain)
            .refreshable {
                await store.refresh(trigger: .foreground)
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        showingGatewaySetup = true
                    } label: {
                        Text("Sessions")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Sessions, gateway settings")
                }
            }
            .nativeSafeAreaBar(edge: .bottom) {
                bottomSearchBar
            }
            .navigationDestination(for: Conversation.ID.self) { id in
                ConversationView(conversationID: id)
            }
        }
        .sheet(isPresented: $showingNewMessage) {
            NewMessageView { recipient in
                Task {
                    if let id = await store.createConversation(recipient: recipient) {
                        path.append(id)
                    }
                }
            }
            .environment(store)
        }
        .sheet(isPresented: $showingGatewaySetup) {
            GatewaySetupView(
                onConnect: { await connectGateway(trigger: .manualConnection) },
                onDisconnect: {
                    store.disconnect()
                    showingGatewaySetup = false
                }
            )
            .environment(gatewayConfiguration)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                if scenePhase == .background {
                    BackgroundSyncCoordinator.shared.schedule()
                }
                return
            }
            guard gatewayConfiguration.isConfigured else {
                showingGatewaySetup = true
                return
            }
            await connectGateway(
                trigger: store.hasCachedSnapshot ? .foreground : .launch
            )
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        for: .seconds(GatewaySyncPolicy.foregroundRefreshInterval)
                    )
                } catch {
                    return
                }
                await store.refresh(trigger: .periodic)
            }
        }
        .alert(
            "Hermes Gateway",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
            Button("Gateway Settings") { showingGatewaySetup = true }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func connectGateway(trigger: GatewaySyncTrigger) async {
        do {
            let client = try gatewayConfiguration.client()
            try await store.connect(to: client, trigger: trigger)
            gatewayConfiguration.errorMessage = nil
            showingGatewaySetup = false
        } catch {
            if error is CancellationError { return }
            if GatewaySyncPolicy.shouldPresentConnectionError(
                trigger: trigger,
                hasCachedSnapshot: store.hasCachedSnapshot
            ) {
                gatewayConfiguration.errorMessage = error.localizedDescription
                showingGatewaySetup = true
            }
        }
    }

    private var bottomSearchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .font(.body)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                Image(systemName: "mic")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 17)
            .frame(height: 46)
            .platformGlass(in: Capsule())

            Button {
                withAnimation(.whoxSmooth) { showingNewMessage = true }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(SmoothPressButtonStyle())
            .platformGlass(in: Circle())
            .accessibilityLabel("New message")
        }
        .padding(.horizontal, 17)
        .padding(.top, 8)
        .padding(.bottom, 1)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 13) {
            ContactAvatar(initials: conversation.initials, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(conversation.timestamp)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(conversation.preview)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .overlay(alignment: .bottomTrailing) {
                if conversation.isMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .offset(x: 20)
                        .transition(.scale(scale: 0.55).combined(with: .opacity))
                        .accessibilityLabel("Alerts hidden")
                }
            }
        }
        .animation(.whoxSmooth, value: conversation.isMuted)
        .animation(.whoxSmooth, value: conversation.isUnread)
        .frame(minHeight: 87)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            if conversation.isUnread {
                Circle()
                    .fill(Color(uiColor: .systemBlue))
                    .frame(width: 10, height: 10)
                    .offset(x: -18)
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
                    .accessibilityLabel("Unread")
            }
        }
    }
}

private struct ConversationContextPreview: View {
    let conversation: Conversation

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    VStack(spacing: 1) {
                        Text("iMessage")
                        Text("Today \(conversation.timestamp)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)

                    if conversation.messages.isEmpty {
                        Text("No Messages")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 28)
                    } else {
                        ForEach(conversation.messages) { message in
                            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 3) {
                                MessageBubble(message: message)
                                if message.sender == .user, message.id == conversation.messages.last?.id {
                                    Text("Delivered")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.trailing, 7)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
        }
        .frame(width: 350, height: 500)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct ConversationView: View {
    @Environment(MessageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let conversationID: Conversation.ID
    @State private var draft = ""
    @State private var hasCompletedInitialLayout = false
    @FocusState private var composerFocused: Bool
    private let transcriptBottomID = "conversation-transcript-bottom"

    private var conversation: Conversation? {
        store.conversation(conversationID)
    }

    private var isSending: Bool {
        store.sendingSessionIDs.contains(conversationID)
    }

    private var isLoading: Bool {
        store.loadingSessionIDs.contains(conversationID)
    }

    var body: some View {
        transcript
            .nativeSafeAreaBar(edge: .top) {
                conversationHeader
            }
            .nativeSafeAreaBar(edge: .bottom) {
                composer
            }
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                store.openConversation(conversationID)
            }
            .onDisappear {
                store.closeConversation(conversationID)
            }
            .task(id: conversationID) {
                await store.loadMessages(for: conversationID)
            }
    }

    private var conversationHeader: some View {
        ZStack(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(SmoothPressButtonStyle())
                .platformGlass(in: Circle())
                .accessibilityLabel("Back")
                Spacer()
            }

            if let conversation {
                NavigationLink {
                    ContactDetailsView(conversationID: conversationID)
                } label: {
                    VStack(spacing: 4) {
                        ContactAvatar(initials: conversation.initials, size: 54)
                        HStack(spacing: 3) {
                            Text(conversation.name)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .platformGlass(in: Capsule())
                    }
                }
                .buttonStyle(SmoothPressButtonStyle())
                .accessibilityLabel("Contact details for \(conversation.name)")
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 7)
        .frame(height: 104, alignment: .top)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    if !(conversation?.messages.isEmpty ?? true) {
                        VStack(spacing: 1) {
                            Text("iMessage")
                            Text("Today 7:13 PM")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 3)
                    }
                    if isLoading && (conversation?.messages.isEmpty ?? true) {
                        ProgressView("Loading session…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 28)
                    }
                    ForEach(conversation?.messages ?? []) { message in
                        VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 3) {
                            MessageBubble(message: message)
                            if message.sender == .user, message.id == conversation?.messages.last?.id {
                                Text("Delivered")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 7)
                            }
                        }
                        .id(message.id)
                        .transition(
                            .scale(
                                scale: 0.72,
                                anchor: message.sender == .user ? .bottomTrailing : .bottomLeading
                            )
                            .combined(with: .opacity)
                        )
                    }

                    if isSending {
                        HStack {
                            HStack(spacing: 5) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Hermes is working…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                Color(uiColor: .systemGray5),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            Spacer(minLength: 56)
                        }
                        .transition(.scale(scale: 0.72, anchor: .bottomLeading).combined(with: .opacity))
                    }

                    Color.clear
                        .frame(height: 15)
                        .id(transcriptBottomID)
                }
                .scrollTargetLayout()
                .padding(.horizontal, 12)
                .padding(.top, 14)
            }
            .initialBottomScrollPosition()
            .nativeSoftScrollEdgeEffect(for: .top)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation?.messages.count) { _, _ in
                withAnimation(.whoxSmooth) {
                    proxy.scrollTo(transcriptBottomID, anchor: .bottom)
                }
            }
            .onChange(of: isSending) { _, _ in
                withAnimation(.whoxSmooth) {
                    proxy.scrollTo(transcriptBottomID, anchor: .bottom)
                }
            }
            .task(id: conversationID) {
                await Task.yield()
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(transcriptBottomID, anchor: .bottom)
                    hasCompletedInitialLayout = true
                }
            }
            .animation(
                hasCompletedInitialLayout ? .whoxSmooth : nil,
                value: conversation?.messages
            )
            .animation(
                hasCompletedInitialLayout ? .whoxSmooth : nil,
                value: isSending
            )
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                Button("Photos", systemImage: "photo") {
                    withAnimation(.whoxSmooth) { draft = "Photo " + draft }
                }
                Button("Camera", systemImage: "camera") {
                    withAnimation(.whoxSmooth) { draft = "Camera " + draft }
                }
                Button("Files", systemImage: "folder") {
                    withAnimation(.whoxSmooth) { draft = "File " + draft }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .regular))
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(SmoothPressButtonStyle())
            .platformGlass(in: Circle())
            .accessibilityLabel("Add attachment")

            HStack(alignment: .bottom, spacing: 7) {
                TextField("Message", text: $draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.leading, 15)
                    .padding(.vertical, 11)

                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 34, height: 44)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .accessibilityLabel("Hermes is working")
                } else if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 44)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .accessibilityHidden(true)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(SmoothPressButtonStyle())
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                    .transition(.scale(scale: 0.65).combined(with: .opacity))
                    .accessibilityLabel("Send")
                }
            }
            .frame(minHeight: 46)
            .platformGlass(in: Capsule())
            .animation(
                .whoxSmooth,
                value: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
            )
        }
        .padding(.horizontal, 17)
        .padding(.top, 7)
        .padding(.bottom, 1)
        .disabled(isLoading)
    }

    private func send() {
        guard !isLoading else { return }
        let value = draft
        withAnimation(.whoxSmooth) {
            draft = ""
        }
        Task { await store.send(value, to: conversationID) }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.sender == .user { Spacer(minLength: 56) }
            Text(message.text)
                .font(.body)
                .foregroundStyle(message.sender == .user ? Color.white : Color.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    message.sender == .user ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray5),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            if message.sender == .contact { Spacer(minLength: 56) }
        }
        .frame(maxWidth: .infinity)
    }
}

extension Animation {
    static let whoxSmooth = Animation.spring(
        response: 0.38,
        dampingFraction: 0.86,
        blendDuration: 0.12
    )
}

struct SmoothPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.whoxSmooth, value: configuration.isPressed)
    }
}

@available(iOS 18.0, *)
private struct InitialBottomScrollPositionModifier: ViewModifier {
    @State private var position = ScrollPosition(idType: String.self, edge: .bottom)

    func body(content: Content) -> some View {
        content.scrollPosition($position, anchor: .bottom)
    }
}

private extension View {
    @ViewBuilder
    func initialBottomScrollPosition() -> some View {
        if #available(iOS 18.0, *) {
            modifier(InitialBottomScrollPositionModifier())
        } else {
            defaultScrollAnchor(.bottom)
        }
    }

    @ViewBuilder
    func nativeSoftScrollEdgeEffect(for edges: Edge.Set) -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }

    @ViewBuilder
    func nativeSafeAreaBar<Content: View>(
        edge: VerticalEdge,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: 0, content: content)
        }
    }
}

struct ContactAvatar: View {
    let initials: String
    let size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.69, green: 0.80, blue: 0.95),
                    Color(red: 0.43, green: 0.47, blue: 0.76),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.65)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var recipient = ""
    @FocusState private var focused: Bool
    let onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("To:")
                        .foregroundStyle(.secondary)
                    TextField("Name", text: $recipient)
                        .focused($focused)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(create)
                }
                .font(.body)
                .padding(.horizontal, 16)
                .frame(height: 50)
                Divider()
                Spacer()
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: create)
                        .disabled(recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { focused = true }
        }
    }

    private func create() {
        guard !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onCreate(recipient)
        dismiss()
    }
}

extension View {
    @ViewBuilder
    func platformGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
    }
}
