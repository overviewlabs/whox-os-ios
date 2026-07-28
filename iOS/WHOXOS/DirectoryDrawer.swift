import SwiftUI
import WHOXCore

struct DirectoryDrawer: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            breadcrumb
            Divider()
            content
        }
        .background(WHOXTheme.background.ignoresSafeArea())
        .task {
            if model.directoryListing == nil { await model.loadDirectory() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(WHOXTheme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("WHOX OS").font(.headline)
                Text("Folders and files").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(WHOXTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close file browser")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var breadcrumb: some View {
        HStack(spacing: 8) {
            if let parent = model.directoryListing?.parent {
                Button {
                    Task { await model.loadDirectory(parent) }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Parent folder")
            }
            Image(systemName: "folder.fill").foregroundStyle(.secondary)
            Text(displayPath)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                Task { await model.loadDirectory(model.directoryListing?.path ?? "") }
            } label: {
                Image(systemName: "arrow.clockwise").frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh directory")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if model.isLoadingDirectory, model.directoryListing == nil {
            Spacer()
            ProgressView("Loading directory…")
            Spacer()
        } else if let error = model.directoryError {
            Spacer()
            ContentUnavailableView("Directory unavailable", systemImage: "folder.badge.questionmark", description: Text(error))
            Spacer()
        } else if let listing = model.directoryListing {
            if listing.data.isEmpty {
                Spacer()
                ContentUnavailableView("Empty folder", systemImage: "folder")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(listing.data) { entry in
                            entryRow(entry)
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .refreshable { await model.loadDirectory(listing.path) }
            }
        } else {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    private func entryRow(_ entry: DirectoryEntry) -> some View {
        Button {
            if entry.isDirectory { Task { await model.loadDirectory(entry.path) } }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon(entry.name))
                    .font(.system(size: 20))
                    .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                    .frame(width: 32, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !entry.isDirectory, let size = entry.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.isDirectory)
        .accessibilityLabel(entry.isDirectory ? "Folder, \(entry.name)" : "File, \(entry.name)")
    }

    private var displayPath: String {
        guard let path = model.directoryListing?.path, !path.isEmpty else { return "/WHOX OS" }
        return "/WHOX OS/" + path
    }

    private func fileIcon(_ name: String) -> String {
        switch name.split(separator: ".").last?.lowercased() {
        case "jpg", "jpeg", "png", "gif", "webp", "heic": "photo"
        case "mp4", "mov": "film"
        case "mp3", "wav", "m4a": "waveform"
        case "swift", "py", "js", "ts", "html", "css", "json", "yaml", "yml": "chevron.left.forwardslash.chevron.right"
        case "pdf": "doc.richtext"
        default: "doc"
        }
    }
}
