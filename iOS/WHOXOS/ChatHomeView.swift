import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import WHOXCore

struct ChatHomeView: View {
    @Environment(AppModel.self) private var model
    let onOpenDrawer: () -> Void
    @State private var draft = ""
    @State private var showingPhotoPicker = false
    @State private var showingFileImporter = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
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
        VStack(spacing: 6) {
            if !model.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.pendingAttachments) { attachment in
                            attachmentChip(attachment)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .accessibilityLabel("Selected attachments")
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") {
                        showingPhotoPicker = true
                    }
                    Button("Files", systemImage: "folder") {
                        showingFileImporter = true
                    }
                    Divider()
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
                    Image(systemName: "plus").font(.title3).frame(width: 44, height: 44)
                }
                .disabled(model.isSending || model.pendingAttachments.count >= 5)
                .accessibilityLabel("Add photos, files, or prompt actions")

                TextField("Ask WHOX OS", text: $draft, axis: .vertical)
                    .lineLimit(1...6).focused($composerFocused).padding(.vertical, 9)

                if !canSend && !model.isSending {
                    Button { composerFocused = true } label: {
                        Image(systemName: "mic.fill").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Voice input")
                    .accessibilityHint("Focuses the composer so you can use iPhone dictation")
                } else {
                    Button(action: submitOrStop) {
                        Image(systemName: model.isSending ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(Color.accentColor, in: Circle())
                            .frame(width: 44, height: 44)
                    }
                    .disabled(!model.isSending && !canSend)
                    .accessibilityLabel(model.isSending ? "Stop response" : "Send message")
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 25).stroke(WHOXTheme.border, lineWidth: 0.7) }
        .padding(.horizontal, 12)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.pendingAttachments.isEmpty
    }
    private func submitOrStop() {
        if model.isSending { model.stopSending(); return }
        guard canSend else { return }
        let value = draft
        draft = ""
        model.submit(value)
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
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
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

    private func suggestion(_ text: String, _ icon: String) -> some View { Button { draft = text + ": "; composerFocused = true } label: { Label(text, systemImage: icon).font(.subheadline).foregroundStyle(.primary).padding(.horizontal, 14).frame(minHeight: 44).background(WHOXTheme.surface, in: Capsule()).overlay { Capsule().stroke(WHOXTheme.border) } } }
    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: icon).frame(width: 44, height: 44).background(WHOXTheme.surface, in: Circle()).overlay { Circle().stroke(WHOXTheme.border, lineWidth: 0.7) } }.accessibilityLabel(label) }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 54) }
            VStack(alignment: .leading, spacing: 10) {
                if !message.content.isEmpty {
                    StructuredChatText(content: message.content)
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
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(ChatPresentation.blocks(content).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
