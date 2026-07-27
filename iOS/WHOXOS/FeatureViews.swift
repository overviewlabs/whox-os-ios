import SwiftUI
import WHOXCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    var body: some View {
        List {
            ForEach(model.sessions.filter { query.isEmpty || ($0.title ?? $0.preview ?? "").localizedCaseInsensitiveContains(query) }) { session in
                NavigationLink { SessionDetailView(session: session) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.title ?? "Untitled chat").font(.body.weight(.medium)).lineLimit(1)
                        if let preview = session.preview { Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                        HStack { Text(session.model ?? session.source ?? "WHOX OS"); Spacer(); Text("\(session.messageCount ?? 0) messages") }.font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 5)
                }.swipeActions { Button("Delete", role: .destructive) { Task { await model.deleteSession(session.id) } } }
            }
        }.searchable(text: $query, prompt: "Search library").refreshable { await model.refreshSessions() }.overlay { if model.sessions.isEmpty && !model.isLoading { ContentUnavailableView("No chats yet", systemImage: "bubble.left.and.bubble.right") } }.task { if model.sessions.isEmpty { await model.refreshSessions() } }
    }
}

private struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    let session: WHOXSession
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(model.messages) { message in
                    VStack(alignment: .leading) {
                        Text(message.role.displayName).font(.caption.bold()).foregroundStyle(.secondary)
                        Group {
                            if let attributed = try? AttributedString(markdown: message.content) { Text(attributed) }
                            else { Text(message.content) }
                        }
                        .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(session.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.selectSession(session.id) }
    }
}

struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var newName = ""
    @State private var showingCreate = false
    private var filteredProjects: [LocalProject] { model.projects.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            ForEach(filteredProjects) { project in
                NavigationLink { ProjectDetailView(projectID: project.id) } label: { Label { VStack(alignment: .leading) { Text(project.name); Text("\(project.sessionIDs.count) chats").font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "folder.fill").foregroundStyle(.blue) } }
            }.onDelete { offsets in
                let ids = offsets.map { filteredProjects[$0].id }
                for id in ids { model.deleteProject(id) }
            }
        }.searchable(text: $query, prompt: "Search projects").overlay { if model.projects.isEmpty { ContentUnavailableView("No projects", systemImage: "folder", description: Text("Organize chats into local projects.")) } }.toolbar { Button { showingCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Create project") }.alert("New project", isPresented: $showingCreate) { TextField("Project name", text: $newName); Button("Cancel", role: .cancel) {}; Button("Create") { model.addProject(newName); newName = "" } }
    }
}

private struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    let projectID: UUID
    var project: LocalProject? { model.projects.first { $0.id == projectID } }
    var body: some View {
        List {
            let assigned = model.sessions.filter { project?.sessionIDs.contains($0.id) == true }
            Section("Project chats") {
                if assigned.isEmpty { Text("No chats assigned yet.").foregroundStyle(.secondary) }
                ForEach(assigned) { session in
                    NavigationLink { SessionDetailView(session: session) } label: { sessionLabel(session) }
                }
            }
            Section("Add or remove chats") {
                ForEach(model.sessions) { session in
                    Button { model.toggleSession(session.id, in: projectID) } label: {
                        HStack {
                            sessionLabel(session)
                            Spacer()
                            Image(systemName: project?.sessionIDs.contains(session.id) == true ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(project?.sessionIDs.contains(session.id) == true ? .blue : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(project?.name ?? "Project")
        .overlay { if model.sessions.isEmpty { ContentUnavailableView("No chats available", systemImage: "bubble.left") } }
    }
    private func sessionLabel(_ session: WHOXSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.title ?? "Untitled chat").lineLimit(1)
            if let preview = session.preview { Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}

struct ScheduledView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCreate = false
    @State private var name = ""
    @State private var schedule = "0 9 * * *"
    @State private var prompt = ""

    var body: some View {
        List {
            ForEach(model.jobs) { job in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(job.name).font(.headline)
                        Spacer()
                        Text(job.statusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(job.enabled == true ? .green : .secondary)
                    }
                    if let prompt = job.prompt {
                        Text(prompt).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text(job.scheduleDisplay ?? job.schedule?.displayString ?? "No schedule")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    HStack {
                        Button("Run now") { Task { await model.jobAction(job.id, .run) } }
                        Spacer()
                        Button(job.enabled == false ? "Resume" : "Pause") {
                            Task { await model.jobAction(job.id, job.enabled == false ? .resume : .pause) }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 5)
                .swipeActions {
                    Button("Delete", role: .destructive) { Task { await model.deleteJob(job.id) } }
                }
            }
        }
        .refreshable { await model.refreshJobs() }
        .task { await model.refreshJobs() }
        .overlay {
            if model.jobs.isEmpty {
                ContentUnavailableView("No scheduled jobs", systemImage: "clock.badge", description: Text("Create an automation backed by the live gateway."))
            }
        }
        .toolbar {
            Button { showingCreate = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("Create scheduled task")
        }
        .sheet(isPresented: $showingCreate) {
            NavigationStack {
                Form {
                    TextField("Name", text: $name)
                    TextField("Cron schedule", text: $schedule)
                    TextField("Prompt", text: $prompt, axis: .vertical).lineLimit(3...8)
                }
                .navigationTitle("New schedule")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingCreate = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            Task {
                                await model.createJob(name: name, schedule: schedule, prompt: prompt)
                                showingCreate = false
                            }
                        }
                        .disabled(name.isEmpty || prompt.isEmpty)
                    }
                }
            }
        }
    }
}

struct PluginsView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selection: InspectorSelection?
    private let keys = ["Capabilities", "Skills", "Toolsets", "Models"]
    var body: some View {
        List {
            ForEach(keys.filter(matches), id: \.self) { key in
                Button {
                    if let value = model.inspector[key] { selection = .init(title: key, value: value) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: key)).frame(width: 30).foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key).font(.headline)
                            Text(summary(for: key)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 54)
                }
                .buttonStyle(.plain)
            }
        }
        .searchable(text: $query, prompt: "Search connected features")
        .refreshable { await model.loadInspector() }
        .task { await model.loadInspector() }
        .overlay { if model.inspector.isEmpty && model.errorMessage == nil { ProgressView("Loading live gateway data") } }
        .sheet(item: $selection) { item in
            NavigationStack {
                ScrollView { JSONValueView(value: item.value).padding() }
                    .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selection = nil } } }
            }
        }
    }
    private func matches(_ key: String) -> Bool {
        query.isEmpty || key.localizedCaseInsensitiveContains(query) || model.inspector[key]?.displayString.localizedCaseInsensitiveContains(query) == true
    }
    private func summary(for key: String) -> String { model.inspector[key]?.displayString ?? "Loading from WHOX OS…" }
    private func icon(for key: String) -> String { ["Capabilities": "switch.2", "Skills": "wand.and.stars", "Toolsets": "wrench.and.screwdriver", "Models": "brain"][key] ?? "puzzlepiece" }
}

private struct InspectorSelection: Identifiable {
    let title: String
    let value: JSONValue
    var id: String { title }
}

struct RemoteView: View {
    @Environment(AppModel.self) private var model
    var body: some View { List { Section("Gateway") { LabeledContent("Endpoint", value: "mobile-api.whox.ai"); LabeledContent("Transport", value: "Authenticated HTTPS + SSE"); LabeledContent("Session", value: model.authenticatedUser == nil ? "Signed out" : "Authenticated") }; Section("Live status") { if let health = model.inspector["Health"] { JSONValueView(value: health) } else { ProgressView() } } }.refreshable { await model.loadInspector() }.task { await model.loadInspector() } }
}

struct HealthView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(model.inspector["Health"] == nil ? "Checking gateway" : "Gateway responded", systemImage: model.inspector["Health"] == nil ? "hourglass" : "checkmark.circle.fill")
                    .font(.headline).foregroundStyle(model.inspector["Health"] == nil ? Color.secondary : Color.green)
                ForEach(healthRows, id: \.0) { key, value in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(value).font(.body.monospaced()).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(WHOXTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(WHOXTheme.border) }
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .refreshable { await model.loadInspector() }.task { await model.loadInspector() }
    }
    private var healthRows: [(String, String)] {
        guard case let .object(values)? = model.inspector["Health"] else { return [] }
        return values.keys.sorted().map { ($0, values[$0]?.displayString ?? "") }
    }
}

struct ImagesView: View {
    @Environment(AppModel.self) private var model
    let openChat: () -> Void
    @State private var prompt = ""
    var body: some View { List { Section("Create") { TextField("Describe an image", text: $prompt, axis: .vertical).lineLimit(2...5); Button { let value = prompt; model.newChat(); model.submit("Create an image: \(value)"); openChat() } label: { Label("Generate with WHOX OS", systemImage: "sparkles") }.disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }; Section("Image chats") { if model.imageSessions.isEmpty { Text("Image generation chats will appear here.").foregroundStyle(.secondary) }; ForEach(model.imageSessions) { session in Button(session.title ?? "Image chat") { Task { await model.selectSession(session.id); openChat() } } } } } }
}

private struct JSONValueView: View {
    let value: JSONValue
    var body: some View { Text(value.displayString).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4) }
}
