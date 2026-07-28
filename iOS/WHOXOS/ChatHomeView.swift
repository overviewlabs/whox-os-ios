import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import WHOXCore

struct ChatHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let onOpenDrawer: () -> Void
    let onOpenDirectory: () -> Void
    @State private var draft = ""
    @State private var voice = VoiceInputService()
    @State private var lastVoiceError: String?
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var showingLinks = false
    @State private var linkInput = ""
    @State private var pendingLinks: [String] = []
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @FocusState private var composerFocused: Bool

    var body: some View {
        ZStack {
            WHOXTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if model.messages.isEmpty {
                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        emptyState
                    } else {
                        Color.clear
                    }
                } else {
                    transcript
                }
                if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 6) }
                composer.padding(.bottom, 8)
            }
        }
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotos,
            maxSelectionCount: max(1, 5 - model.pendingAttachments.count),
            matching: .images,
            preferredItemEncoding: .compatible
        )
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items); selectedPhotos = [] }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: allowedDocumentTypes,
            allowsMultipleSelection: true
        ) { result in
            importFiles(result)
        }
        .sheet(isPresented: $showingLinks) { linkEditor }
        .onChange(of: voice.transcript) { _, value in
            if voice.isRecording || !value.isEmpty { draft = value }
        }
        .onChange(of: voice.errorMessage) { _, value in
            if let value {
                lastVoiceError = value
                model.errorMessage = value
            } else if model.errorMessage == lastVoiceError {
                model.errorMessage = nil
                lastVoiceError = nil
            }
        }
        .onDisappear { voice.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voice.cancel() }
        }
        .task {
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains(where: { $0.hasPrefix("--visual-review-") }) {
                model.errorMessage = nil
                try? await Task.sleep(for: .milliseconds(500))
                model.errorMessage = nil
            }
            if arguments.contains("--visual-review-composer-typed") {
                draft = "Hi"
                try? await Task.sleep(for: .milliseconds(350))
                composerFocused = true
            }
            if arguments.contains("--visual-review-composer-links") {
                draft = "Compare these sources"
                pendingLinks = ["https://whox.ai/docs", "https://example.com/reference"]
            }
#endif
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: onOpenDrawer) {
                ZStack {
                    Circle().fill(WHOXTheme.surface).frame(width: 40, height: 40)
                    Circle().stroke(WHOXTheme.border, lineWidth: 0.7).frame(width: 40, height: 40)
                    MenuGlyph()
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open navigation")
            Spacer()
            HStack(spacing: 6) {
                Text("Chat")
                    .font(.system(size: 17, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 72, minHeight: 44)
            .accessibilityLabel("Chat")
            Spacer()
            circleButton("sidebar.right", label: "Open folders and files", action: onOpenDirectory)
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                suggestion("photo", "Create an image", prompt: "Create an image: ")
                suggestion("pencil", "Write or edit", prompt: "Help me write or edit: ")
                suggestion("globe", "Search the web", prompt: "Search the web for: ")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
        }
    }

    private var transcript: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(model.messages) { message in
                            MessageRow(
                                message: message,
                                maximumWidth: ChatBubbleContract.maximumWidth(containerWidth: geometry.size.width)
                            )
                            .id(message.id)
                        }
                        if model.isSending { ProgressView().controlSize(.small).padding(.horizontal, 20).accessibilityLabel("WHOX OS is responding") }
                    }.padding(.vertical, 14)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.messages.last?.content) { _, _ in if let id = model.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if !model.pendingAttachments.isEmpty || !pendingLinks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingLinks, id: \.self) { link in
                            linkChip(link)
                        }
                        ForEach(model.pendingAttachments) { attachment in
                            attachmentChip(attachment)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .accessibilityLabel("Selected attachments")
            }

            HStack(spacing: 0) {
                Menu {
                    Button("Links", systemImage: "link") {
                        linkInput = pendingLinks.joined(separator: "\n")
                        showingLinks = true
                    }
                    Button("Files", systemImage: "folder") { showingFileImporter = true }
                        .disabled(model.pendingAttachments.count >= 5)
                    Button("Photo Library", systemImage: "photo.on.rectangle") { showingPhotoPicker = true }
                        .disabled(model.pendingAttachments.count >= 5)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isSending)
                .accessibilityLabel("Add links, files, or photos")

                TextField("Ask WHOX OS", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .submitLabel(.send)
                    .onSubmit {
                        guard !voice.isFinalizing, canSend || model.isSending else { return }
                        submitOrStop()
                    }
                    .focused($composerFocused)
                    .frame(maxWidth: .infinity, minHeight: 44)

                Button(action: toggleVoiceInput) {
                    Image(systemName: (voice.isRecording || voice.isStarting) ? "stop.circle.fill" : "mic")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle((voice.isRecording || voice.isStarting) ? .red : .primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isSending || voice.isFinalizing)
                .accessibilityLabel((voice.isRecording || voice.isStarting) ? "Stop transcription" : "Start transcription")

                trailingComposerControl
                    .frame(width: ComposerContract.trailingSlot, height: 44)
            }
            .padding(.horizontal, 4)
            .frame(height: ComposerContract.containerHeight)
            .background(WHOXTheme.surface, in: Capsule())
            .overlay { Capsule().stroke(WHOXTheme.border, lineWidth: 0.7) }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder private var trailingComposerControl: some View {
        switch ComposerContract.trailingControl(
            draft: draft,
            isSending: model.isSending,
            isRecording: voice.isRecording || voice.isStarting,
            isFinalizing: voice.isFinalizing
        ) {
        case .microphone:
            Button(action: toggleVoiceInput) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WHOXTheme.background)
                    .frame(width: 34, height: 34)
                    .background(Color.primary, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start voice transcription")
        case .liveAudio:
            Button(action: toggleVoiceInput) {
                LiveAudioBars(level: voice.level)
                    .foregroundStyle(WHOXTheme.background)
                    .frame(width: 34, height: 34)
                    .background(Color.primary, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recording. Stop transcription")
        case .finalizing:
            ProgressView()
                .controlSize(.small)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Finalizing transcription")
        case .send:
            Button(action: submitOrStop) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WHOXTheme.background)
                    .frame(width: 34, height: 34)
                    .background(Color.primary, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        case .stop:
            Button(action: submitOrStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WHOXTheme.background)
                    .frame(width: 34, height: 34)
                    .background(Color.primary, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop response")
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !model.pendingAttachments.isEmpty || !pendingLinks.isEmpty
    }

    private func submitOrStop() {
        if model.isSending { model.stopSending(); return }
        if voice.isRecording { voice.stop(); return }
        if voice.isStarting { voice.cancel(); return }
        if voice.isFinalizing { return }
        guard canSend else { return }
        let value = LinkReferenceContract.messageText(draft: draft, links: pendingLinks)
        draft = ""
        pendingLinks = []
        model.submit(value)
    }

    private var linkEditor: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add one web address per line. WHOX OS will use these links as references for your message.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextEditor(text: $linkInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(8)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(WHOXTheme.border) }
                    .accessibilityLabel("Reference links, one per line")
            }
            .padding(18)
            .navigationTitle("Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingLinks = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let links = LinkReferenceContract.validLinks(from: linkInput)
                        if links.isEmpty && !linkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            model.errorMessage = "Enter at least one valid http or https link."
                            return
                        }
                        pendingLinks = links
                        model.errorMessage = nil
                        showingLinks = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggleVoiceInput() {
        if voice.isRecording {
            voice.stop()
        } else if voice.isStarting {
            voice.cancel()
        } else if voice.isFinalizing {
            return
        } else {
            composerFocused = false
            Task { await voice.start(existingText: draft) }
        }
    }

    private func suggestion(_ icon: String, _ title: String, prompt: String) -> some View {
        Button {
            draft = prompt
            composerFocused = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.system(size: 15))
                Spacer()
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var allowedDocumentTypes: [UTType] {
        let extensions = ["pdf", "txt", "md", "csv", "json", "rtf", "docx", "xlsx", "pptx"]
        return [.image] + extensions.compactMap { UTType(filenameExtension: $0) }
    }

    @ViewBuilder
    private func attachmentChip(_ attachment: PendingChatAttachment) -> some View {
        HStack(spacing: 8) {
            if attachment.isImage, let image = UIImage(data: attachment.data) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name).font(.caption.weight(.medium)).lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Button { model.removeAttachment(attachment.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 44)
            }
            .disabled(model.isSending)
            .accessibilityLabel("Remove \(attachment.name)")
        }
        .padding(.leading, 5).padding(.trailing, 3).padding(.vertical, 4)
        .frame(maxWidth: 260)
        .background(WHOXTheme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(WHOXTheme.border, lineWidth: 0.7) }
        .accessibilityElement(children: .contain)
    }

    private func linkChip(_ link: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.08), in: Circle())
            Text(URL(string: link)?.host ?? link)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Button { pendingLinks.removeAll { $0 == link } } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 44)
            }
            .disabled(model.isSending)
            .accessibilityLabel("Remove link \(link)")
        }
        .padding(.leading, 5).padding(.trailing, 3).padding(.vertical, 4)
        .frame(maxWidth: 260)
        .background(WHOXTheme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(WHOXTheme.border, lineWidth: 0.7) }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items.prefix(max(0, 5 - model.pendingAttachments.count)) {
            do {
                guard let source = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: source),
                      let jpeg = image.jpegData(compressionQuality: 0.9) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                model.addAttachment(name: "Photo-\(UUID().uuidString.prefix(8)).jpg", mimeType: "image/jpeg", data: jpeg)
            } catch {
                model.errorMessage = "One of the selected photos could not be attached."
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            for url in urls.prefix(max(0, 5 - model.pendingAttachments.count)) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 20 * 1024 * 1024 else {
                    model.errorMessage = "Each attachment must be 20 MB or smaller."
                    continue
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let ext = url.pathExtension.lowercased()
                if ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"].contains(ext),
                   let image = UIImage(data: data),
                   let jpeg = image.jpegData(compressionQuality: 0.9) {
                    model.addAttachment(name: url.deletingPathExtension().lastPathComponent + ".jpg", mimeType: "image/jpeg", data: jpeg)
                } else if let mimeType = documentMIMEType(for: ext) {
                    model.addAttachment(name: url.lastPathComponent, mimeType: mimeType, data: data)
                } else {
                    model.errorMessage = "That file type is not supported."
                }
            }
        } catch {
            model.errorMessage = "The selected file could not be attached."
        }
    }

    private func documentMIMEType(for ext: String) -> String? {
        [
            "pdf": "application/pdf", "txt": "text/plain", "md": "text/markdown",
            "csv": "text/csv", "json": "application/json", "rtf": "application/rtf",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        ][ext]
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(WHOXTheme.surface).frame(width: 40, height: 40)
                Circle().stroke(WHOXTheme.border, lineWidth: 0.7).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct MenuGlyph: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().frame(width: 20, height: 1.5)
            Capsule().frame(width: 12, height: 1.5)
        }
        .frame(width: 22, height: 22, alignment: .center)
    }
}

private struct LiveAudioBars: View {
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .frame(width: 2.2, height: barHeight(index))
                    .animation(.linear(duration: 0.09), value: level)
            }
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let multipliers: [Double] = [0.55, 0.82, 1, 0.72, 0.48]
        return 5 + CGFloat(max(level, 0.06) * 13 * multipliers[index])
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let maximumWidth: CGFloat

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 54) }
            VStack(alignment: .leading, spacing: 10) {
                if !message.content.isEmpty {
                    StructuredChatText(
                        content: message.content,
                        expandsHorizontally: message.role != .user
                    )
                }
                ForEach(message.attachments) { attachment in
                    HistoryAttachmentCard(attachment: attachment)
                }
            }
            .padding(message.role == .user ? 12 : 0)
            .background(
                message.role == .user ? WHOXTheme.surface : Color.clear,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .frame(maxWidth: maximumWidth, alignment: message.role == .user ? .trailing : .leading)
            if message.role != .user { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 16)
    }
}

private struct HistoryAttachmentCard: View {
    @Environment(AppModel.self) private var model
    let attachment: ChatAttachment
    @State private var imageData: Data?
    @State private var didFail = false

    var body: some View {
        Group {
            if attachment.isImage {
                imageCard
            } else {
                fileCard
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attachment \(attachment.name), \(formattedSize)")
    }

    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if didFail {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: 280, minHeight: 96, maxHeight: 260)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 6) {
                Image(systemName: "photo")
                Text(attachment.name).lineLimit(1)
                Spacer(minLength: 6)
                Text(formattedSize).foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .task(id: attachment.id) {
            imageData = await model.attachmentData(attachment)
            didFail = imageData == nil
        }
    }

    private var fileCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name).font(.subheadline.weight(.medium)).lineLimit(2)
                Text(formattedSize).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .frame(maxWidth: 280, alignment: .leading)
        .background(WHOXTheme.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(WHOXTheme.border, lineWidth: 0.7) }
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file)
    }
}

private struct StructuredChatText: View {
    let content: String
    let expandsHorizontally: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(ChatPresentation.blocks(content).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: expandsHorizontally ? .infinity : nil, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: ChatContentBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineMarkdown(text)
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 2 : 0)
        case .paragraph(let text):
            inlineMarkdown(text)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•").font(.body.weight(.semibold))
                        inlineMarkdown(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                        inlineMarkdown(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .quote(let text):
            inlineMarkdown(text)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 13)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 3)
                }
        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 8) {
                if let language { Text(language.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.callout, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WHOXTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(WHOXTheme.border, lineWidth: 0.7) }
        case .divider:
            Divider()
        }
    }

    private func inlineMarkdown(_ source: String) -> Text {
        guard let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return Text(source) }
        return Text(attributed)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline
        default: .subheadline.weight(.semibold)
        }
    }
}
