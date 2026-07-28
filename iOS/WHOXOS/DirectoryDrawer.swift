import QuickLook
import SwiftUI
import UIKit
import WHOXCore

struct DirectoryDrawer: View {
    @Bindable var model: AppModel
    let onClose: () -> Void

    @State private var preview: DirectoryPreview?
    @State private var previewFolderURL: URL?
    @State private var loadingFilePath: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            pathBar

            ZStack {
                if model.isLoadingDirectory && model.directoryListing == nil {
                    ProgressView("Loading root…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.directoryError, model.directoryListing == nil {
                    ContentUnavailableView(
                        "Directory unavailable",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(error)
                    )
                } else if let listing = model.directoryListing {
                    directoryList(listing)
                        .id(listing.path)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                if model.isLoadingDirectory && model.directoryListing != nil {
                    ProgressView()
                        .padding(12)
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel("Loading directory")
                }
            }
        }
        .background(WHOXTheme.background)
        .task {
            if model.directoryListing == nil { await model.loadDirectory("") }
        }
        .sheet(item: $preview, onDismiss: removePreview) { item in
            DirectoryQuickLook(url: item.url)
                .ignoresSafeArea()
        }
        .accessibilityAction(.escape, onClose)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 46, height: 46)
                .background(Color.primary.opacity(0.08), in: Circle())
                .overlay { Circle().stroke(WHOXTheme.border, lineWidth: 0.7) }

            VStack(alignment: .leading, spacing: 2) {
                Text("WHOX OS").font(.system(size: 21, weight: .semibold))
                Text("Folders and files · read only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 46, height: 46)
                    .background(Color.primary.opacity(0.08), in: Circle())
                    .overlay { Circle().stroke(WHOXTheme.border, lineWidth: 0.7) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close directory")
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var pathBar: some View {
        HStack(spacing: 10) {
            Button {
                if let parent = model.directoryListing?.parent {
                    navigate(to: parent)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled((model.directoryListing?.path ?? "").isEmpty || model.isLoadingDirectory)
            .accessibilityLabel("Back one folder")

            Image(systemName: "folder.fill").foregroundStyle(.secondary)
            Text(DirectoryPathContract.displayPath(model.directoryListing?.path ?? ""))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("Current directory \(DirectoryPathContract.displayPath(model.directoryListing?.path ?? ""))")
            Spacer(minLength: 4)
            Button {
                Task { await model.loadDirectory(model.directoryListing?.path ?? "") }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(model.isLoadingDirectory)
            .accessibilityLabel("Refresh directory")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func directoryList(_ listing: DirectoryListing) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let error = model.directoryError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }

                if listing.data.isEmpty {
                    ContentUnavailableView("Empty folder", systemImage: "folder")
                        .padding(.top, 72)
                } else {
                    ForEach(Array(listing.data.enumerated()), id: \.element.id) { index, entry in
                        directoryRow(entry)
                        if index < listing.data.count - 1 { Divider().padding(.leading, 70) }
                    }
                }

            }
        }
        .scrollIndicators(.visible)
    }

    private func directoryRow(_ entry: DirectoryEntry) -> some View {
        Button {
            if entry.isDirectory {
                navigate(to: entry.path)
            } else {
                previewFile(entry)
            }
        } label: {
            HStack(spacing: 15) {
                Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon(entry.name))
                    .font(.title3)
                    .foregroundStyle(Color.primary)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !entry.isDirectory, let size = entry.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
                if loadingFilePath == entry.path {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: entry.isDirectory ? "chevron.right" : "eye")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .frame(minHeight: 64)
        }
        .buttonStyle(.plain)
        .disabled(loadingFilePath != nil)
        .contextMenu {
            if !entry.isDirectory {
                Button {
                    previewFile(entry)
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                Button {
                    addToChat(entry)
                } label: {
                    Label("Add to Chat", systemImage: "paperclip")
                }
            }
        }
        .accessibilityLabel(entryAccessibilityLabel(entry))
        .accessibilityHint(entry.isDirectory ? "Opens this folder" : "Opens a read-only preview")
        .accessibilityAction(named: "Add to Chat") {
            if !entry.isDirectory { addToChat(entry) }
        }
    }

    private func entryAccessibilityLabel(_ entry: DirectoryEntry) -> String {
        guard !entry.isDirectory else { return "Folder, \(entry.name)" }
        if let size = entry.size {
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            return "File, \(entry.name), \(formatted), preview"
        }
        return "File, \(entry.name), preview"
    }

    private func navigate(to path: String) {
        withAnimation(.snappy(duration: 0.28)) {
            Task { await model.loadDirectory(path) }
        }
    }

    private func previewFile(_ entry: DirectoryEntry) {
        guard loadingFilePath == nil else { return }
        loadingFilePath = entry.path
        Task {
            defer { loadingFilePath = nil }
            guard let data = await model.directoryFileData(entry) else { return }
            do {
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("WHOXDirectoryPreviews", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete]
                )
                guard let safeName = PreviewFilenameContract.safeFilename(entry.name) else {
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                let url = folder.appendingPathComponent(safeName, isDirectory: false)
                guard url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else {
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                previewFolderURL = folder
                preview = DirectoryPreview(url: url)
            } catch {
                model.errorMessage = "The file preview could not be prepared."
            }
        }
    }

    private func addToChat(_ entry: DirectoryEntry) {
        guard loadingFilePath == nil else { return }
        loadingFilePath = entry.path
        Task {
            defer { loadingFilePath = nil }
            if await model.addDirectoryAttachment(entry) {
                onClose()
            }
        }
    }

    private func removePreview() {
        guard let folder = previewFolderURL else { return }
        try? FileManager.default.removeItem(at: folder)
        previewFolderURL = nil
        preview = nil
    }

    private func fileIcon(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        case "pdf": return "doc.richtext"
        case "swift", "py", "js", "ts", "html", "css", "sh": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}

private struct DirectoryPreview: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DirectoryQuickLook: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
