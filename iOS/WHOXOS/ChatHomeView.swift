import SwiftUI
import WHOXCore

struct ChatHomeView: View {
    @Environment(AppModel.self) private var model
    let onOpenDrawer: () -> Void
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        ZStack {
            WHOXTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if model.messages.isEmpty { emptyState } else { transcript }
                if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 6) }
                composer.padding(.bottom, 8)
            }
        }
    }

    private var topBar: some View {
        HStack {
            circleButton("line.3.horizontal", label: "Open navigation", action: onOpenDrawer)
            Spacer()
            Text(model.selectedSession?.title ?? "WHOX OS").font(.headline).lineLimit(1).padding(.horizontal, 8)
            Spacer()
            circleButton("square.and.pencil", label: "New chat") { model.newChat() }
        }.padding(.horizontal, 14).padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("WHOXStudioLogo").resizable().scaledToFit().frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 12))
            Text("How can I help?").font(.title2.bold()).padding(.top, 14)
            Spacer()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    suggestion("Create an image", "photo")
                    suggestion("Write or edit", "pencil")
                    suggestion("Look something up", "globe")
                }.padding(.horizontal, 16)
            }.padding(.bottom, 12)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(model.messages) { message in MessageRow(message: message).id(message.id) }
                    if model.isSending { ProgressView().controlSize(.small).padding(.horizontal, 20).accessibilityLabel("WHOX OS is responding") }
                }.padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.last?.content) { _, _ in if let id = model.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button("New chat", systemImage: "square.and.pencil") {
                    model.newChat(); draft = ""; composerFocused = true
                }
                Button("Create an image", systemImage: "photo.badge.plus") {
                    draft = "Create an image: "; composerFocused = true
                }
                Button("Write or edit", systemImage: "pencil.line") {
                    draft = "Help me write or edit: "; composerFocused = true
                }
                Button("Look something up", systemImage: "magnifyingglass") {
                    draft = "Look up and explain: "; composerFocused = true
                }
            } label: {
                Image(systemName: "plus").font(.title3).frame(width: 36, height: 36)
            }
            .accessibilityLabel("Prompt actions")

            TextField("Ask WHOX OS", text: $draft, axis: .vertical)
                .lineLimit(1...6).focused($composerFocused).padding(.vertical, 9)

            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isSending {
                Button { composerFocused = true } label: {
                    Image(systemName: "mic.fill").frame(width: 36, height: 36)
                }
                .accessibilityLabel("Voice input")
                .accessibilityHint("Focuses the composer so you can use iPhone dictation")
            } else {
                Button(action: submitOrStop) {
                    Image(systemName: model.isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(Color.accentColor, in: Circle())
                }
                .disabled(!model.isSending && !canSend)
                .accessibilityLabel(model.isSending ? "Stop response" : "Send message")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 25).stroke(WHOXTheme.border, lineWidth: 0.7) }
        .padding(.horizontal, 12)
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func submitOrStop() {
        if model.isSending { model.stopSending(); return }
        guard canSend else { return }
        let value = draft
        draft = ""
        model.submit(value)
    }
    private func suggestion(_ text: String, _ icon: String) -> some View { Button { draft = text + ": "; composerFocused = true } label: { Label(text, systemImage: icon).font(.subheadline).foregroundStyle(.primary).padding(.horizontal, 14).frame(minHeight: 44).background(WHOXTheme.surface, in: Capsule()).overlay { Capsule().stroke(WHOXTheme.border) } } }
    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: icon).frame(width: 44, height: 44).background(WHOXTheme.surface, in: Circle()).overlay { Circle().stroke(WHOXTheme.border, lineWidth: 0.7) } }.accessibilityLabel(label) }
}

private struct MessageRow: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 54) }
            VStack(alignment: .leading, spacing: 10) {
                markdown
                if let calls = message.toolCalls, !calls.isEmpty {
                    ForEach(Array(calls.enumerated()), id: \.offset) { _, call in
                        DisclosureGroup { Text(call.result?.displayString ?? call.arguments?.displayString ?? "").font(.caption.monospaced()).textSelection(.enabled) } label: { Label(call.name ?? "Tool", systemImage: call.status == "completed" ? "checkmark.circle" : "wrench.and.screwdriver").font(.caption.weight(.medium)) }
                    }
                }
                if let reasoning = message.reasoning, !reasoning.isEmpty { DisclosureGroup("Reasoning") { Text(reasoning).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }.font(.caption) }
            }
            .padding(message.role == .user ? 12 : 0)
            .background(message.role == .user ? WHOXTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if message.role != .user { Spacer(minLength: 0) }
        }.padding(.horizontal, 16)
    }
    private var markdown: Text { (try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .full))) .map { Text($0) } ?? Text(message.content) }
}
