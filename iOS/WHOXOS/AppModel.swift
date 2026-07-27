import Foundation
import Observation
import WHOXCore

struct LocalProject: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sessionIDs: [String] = []
    var createdAt = Date()
}

@MainActor @Observable
final class AppModel {
    enum Connection: Equatable { case unpaired, connecting, connected(serverName: String), failed(message: String) }
    enum AuthenticationState: Equatable { case checking, signedOut, signedIn(AuthenticatedUser) }

    var connection: Connection = .unpaired
    var authenticationState: AuthenticationState = .checking
    var isAuthenticating = false
    var authenticationError: String?
    var sessions: [WHOXSession] = []
    var selectedSessionID: String?
    var messages: [ChatMessage] = []
    var jobs: [ScheduledJob] = []
    var projects: [LocalProject] = []
    var pinnedSessionIDs: Set<String> = []
    var inspector: [String: JSONValue] = [:]
    var isLoading = false
    var isSending = false
    var errorMessage: String?
    var activeRunID: String?
    var pendingApproval: RunEvent?

    private let authenticationService: AuthenticationService
    private let gateway: GatewayService
    private let defaults = UserDefaults.standard
    @ObservationIgnored private var chatTask: Task<Void, Never>?
    @ObservationIgnored private var chatOperationID: UUID?
    @ObservationIgnored private var sessionLoadID: UUID?
    @ObservationIgnored private var accountGeneration = 0

    init() {
        let authenticationService = AuthenticationService()
        self.authenticationService = authenticationService
        self.gateway = GatewayService(auth: authenticationService)
        defaults.removeObject(forKey: "whox.projects")
        defaults.removeObject(forKey: "whox.pinnedSessions")
    }

    var selectedSession: WHOXSession? { sessions.first { $0.id == selectedSessionID } }
    var authenticatedUser: AuthenticatedUser? { guard case let .signedIn(user) = authenticationState else { return nil }; return user }
    var imageSessions: [WHOXSession] { sessions.filter { (($0.title ?? "") + " " + ($0.preview ?? "")).localizedCaseInsensitiveContains("image") } }

    func restoreAuthenticationIfNeeded() async {
        guard authenticationState == .checking else { return }
        do {
            if let session = try await authenticationService.restoreSession() {
                activateAccount(session.user)
                await refreshSessions()
            } else { transitionToSignedOut() }
        } catch { transitionToSignedOut(); authenticationError = nil }
    }

    func signIn(email: String, password: String) async {
        guard !isAuthenticating else { return }; isAuthenticating = true; authenticationError = nil
        defer { isAuthenticating = false }
        do {
            let session = try await authenticationService.signIn(email: email, password: password)
            activateAccount(session.user)
            await refreshSessions()
        } catch { authenticationError = (error as? LocalizedError)?.errorDescription ?? AuthenticationError.unavailable.localizedDescription }
    }

    func signOut() async {
        transitionToSignedOut()
        authenticationError = nil
        await authenticationService.signOut()
    }

    func refreshSessions() async {
        let generation = accountGeneration
        guard authenticatedUser != nil else { return }
        isLoading = true
        defer { if generation == accountGeneration { isLoading = false } }
        do {
            let loaded = try await gateway.sessions().sorted { $0.activityTimestamp > $1.activityTimestamp }
            guard generation == accountGeneration else { return }
            sessions = loaded
            connection = .connected(serverName: "mobile-api.whox.ai")
            errorMessage = nil
        } catch {
            guard generation == accountGeneration else { return }
            handle(error)
        }
    }

    func selectSession(_ id: String?) async {
        discardChat()
        let requestID = UUID()
        sessionLoadID = requestID
        selectedSessionID = id
        messages = []
        guard let id else { return }
        isLoading = true
        defer { if sessionLoadID == requestID { isLoading = false } }
        do {
            let loaded = try await gateway.messages(id)
            guard sessionLoadID == requestID, selectedSessionID == id else { return }
            messages = loaded
            errorMessage = nil
        } catch {
            guard sessionLoadID == requestID else { return }
            handle(error)
        }
    }

    func newChat() {
        discardChat()
        sessionLoadID = UUID()
        selectedSessionID = nil
        messages = []
        errorMessage = nil
    }

    func submit(_ raw: String) {
        guard chatTask == nil else { return }
        let operationID = UUID()
        chatOperationID = operationID
        chatTask = Task { [weak self] in
            guard let self else { return }
            await self.performSend(raw, operationID: operationID)
            self.finishChat(operationID)
        }
    }

    func stopSending() { chatTask?.cancel() }

    private func performSend(_ raw: String, operationID: UUID) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, chatOperationID == operationID else { return }
        isSending = true
        errorMessage = nil
        do {
            if selectedSessionID == nil {
                let session = try await gateway.createSession(title: String(text.prefix(56)))
                try Task.checkCancellation()
                guard chatOperationID == operationID else { return }
                selectedSessionID = session.id
                sessions.insert(session, at: 0)
            }
            try Task.checkCancellation()
            guard chatOperationID == operationID else { return }
            messages.append(ChatMessage(id: "local-user-\(UUID())", role: .user, content: text, timestamp: Date().timeIntervalSince1970))
            let assistantID = "stream-\(UUID())"
            messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
            guard let selectedSessionID else { throw GatewayError.invalidResponse }
            try await gateway.streamChat(sessionID: selectedSessionID, message: text) { [weak self] event in
                guard let self, self.chatOperationID == operationID else { return }
                switch event {
                case .delta(let delta):
                    if let i = self.messages.firstIndex(where: { $0.id == assistantID }) { self.messages[i].content += delta }
                case .message(let message):
                    if let i = self.messages.firstIndex(where: { $0.id == assistantID }) { self.messages[i] = message }
                case .session(let id): self.selectedSessionID = id
                case .error(let message): self.errorMessage = message
                case .done: break
                }
            }
            try Task.checkCancellation()
            guard chatOperationID == operationID else { return }
            if let i = messages.firstIndex(where: { $0.id == assistantID }), messages[i].content.isEmpty { messages.remove(at: i) }
            await refreshSessions()
        } catch is CancellationError {
            removeEmptyAssistant(operationID)
        } catch let error as URLError where error.code == .cancelled {
            removeEmptyAssistant(operationID)
        } catch {
            guard chatOperationID == operationID else { return }
            handle(error)
        }
    }

    private func finishChat(_ operationID: UUID) {
        guard chatOperationID == operationID else { return }
        chatTask = nil
        chatOperationID = nil
        isSending = false
    }

    private func discardChat() {
        chatTask?.cancel()
        chatTask = nil
        chatOperationID = nil
        isSending = false
        activeRunID = nil
        pendingApproval = nil
    }

    private func removeEmptyAssistant(_ operationID: UUID) {
        guard chatOperationID == operationID else { return }
        if messages.last?.role == .assistant, messages.last?.content.isEmpty == true { messages.removeLast() }
    }

    func renameSession(_ id: String, title: String) async {
        let generation = accountGeneration
        do {
            try await gateway.renameSession(id, title: title)
            guard generation == accountGeneration else { return }
            await refreshSessions()
        } catch { if generation == accountGeneration { handle(error) } }
    }

    func deleteSession(_ id: String) async {
        let generation = accountGeneration
        do {
            try await gateway.deleteSession(id)
            guard generation == accountGeneration else { return }
            pinnedSessionIDs.remove(id)
            if selectedSessionID == id { newChat() }
            await refreshSessions()
            savePins()
        } catch { if generation == accountGeneration { handle(error) } }
    }

    func togglePin(_ id: String) {
        guard authenticatedUser != nil else { return }
        if pinnedSessionIDs.contains(id) { pinnedSessionIDs.remove(id) } else { pinnedSessionIDs.insert(id) }
        savePins()
    }

    func refreshJobs() async {
        let generation = accountGeneration
        do {
            let loaded = try await gateway.jobs()
            guard generation == accountGeneration else { return }
            jobs = loaded
            errorMessage = nil
        } catch { if generation == accountGeneration { handle(error) } }
    }

    func createJob(name: String, schedule: String, prompt: String) async {
        let generation = accountGeneration
        do {
            try await gateway.createJob(name: name, schedule: schedule, prompt: prompt)
            guard generation == accountGeneration else { return }
            await refreshJobs()
        } catch { if generation == accountGeneration { handle(error) } }
    }

    func deleteJob(_ id: String) async {
        let generation = accountGeneration
        do {
            try await gateway.deleteJob(id)
            guard generation == accountGeneration else { return }
            await refreshJobs()
        } catch { if generation == accountGeneration { handle(error) } }
    }

    func jobAction(_ id: String, _ action: JobAction) async {
        let generation = accountGeneration
        do {
            try await gateway.jobAction(id, action)
            guard generation == accountGeneration else { return }
            await refreshJobs()
        } catch { if generation == accountGeneration { handle(error) } }
    }

    func loadInspector() async {
        let generation = accountGeneration
        do {
            async let capabilities = gateway.capabilities(); async let skills = gateway.skills(); async let toolsets = gateway.toolsets(); async let models = gateway.models(); async let health = gateway.health()
            let loaded = ["Capabilities": try await capabilities, "Skills": try await skills, "Toolsets": try await toolsets, "Models": try await models, "Health": try await health]
            guard generation == accountGeneration else { return }
            inspector = loaded
            errorMessage = nil
        } catch { if generation == accountGeneration { handle(error) } }
    }

    func addProject(_ name: String) { let value = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }; projects.insert(.init(name: value), at: 0); saveProjects() }
    func deleteProject(_ id: UUID) { projects.removeAll { $0.id == id }; saveProjects() }
    func toggleSession(_ sessionID: String, in projectID: UUID) { guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }; if projects[i].sessionIDs.contains(sessionID) { projects[i].sessionIDs.removeAll { $0 == sessionID } } else { projects[i].sessionIDs.append(sessionID) }; saveProjects() }

    private func saveProjects() {
        guard let userID = authenticatedUser?.id else { return }
        defaults.set(try? JSONEncoder().encode(projects), forKey: storageKey("projects", userID: userID))
    }

    private func savePins() {
        guard let userID = authenticatedUser?.id else { return }
        defaults.set(Array(pinnedSessionIDs), forKey: storageKey("pinnedSessions", userID: userID))
    }

    private func storageKey(_ value: String, userID: String) -> String { "whox.\(value).user.\(userID)" }

    private func activateAccount(_ user: AuthenticatedUser) {
        accountGeneration += 1
        discardChat()
        sessionLoadID = UUID()
        clearAccountData()
        authenticationState = .signedIn(user)
        if let data = defaults.data(forKey: storageKey("projects", userID: user.id)),
           let stored = try? JSONDecoder().decode([LocalProject].self, from: data) { projects = stored }
        pinnedSessionIDs = Set(defaults.stringArray(forKey: storageKey("pinnedSessions", userID: user.id)) ?? [])
    }

    private func transitionToSignedOut() {
        accountGeneration += 1
        discardChat()
        sessionLoadID = UUID()
        clearAccountData()
        authenticationState = .signedOut
        connection = .unpaired
        isLoading = false
    }

    private func clearAccountData() {
        sessions = []
        selectedSessionID = nil
        messages = []
        jobs = []
        projects = []
        pinnedSessionIDs = []
        inspector = [:]
        errorMessage = nil
        activeRunID = nil
        pendingApproval = nil
    }

    private func handle(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if case AuthenticationError.sessionExpired = error {
            transitionToSignedOut()
            Task { await authenticationService.signOut() }
        }
    }
}
