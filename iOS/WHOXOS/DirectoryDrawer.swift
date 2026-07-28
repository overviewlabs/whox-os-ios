import SwiftUI
import WHOXCore

struct DirectoryDrawer: View {
    @Environment(AppModel.self) private var model
    @AccessibilityFocusState private var closeFocused: Bool
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
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .task {
            closeFocused = true
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
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close file browser")
            .accessibilityFocused($closeFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var breadcrumb: some View {
        HStack(spacing: 8) {
            if let parent = requestedParent {
                Button {
                    Task { await model.loadDirectory(parent) }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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
                Task { await model.loadDirectory(model.requestedDirectoryPath) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh directory")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder private var content: some View {
        if model.isLoadingDirectory, model.directoryListing == nil {
            Spacer()
            ProgressView("Loading directory…")
            Spacer()
        } else if let error = model.directoryError {
            Spacer()
            VStack(spacing: 16) {
                ContentUnavailableView("Directory unavailable", systemImage: "folder.badge.questionmark", description: Text(error))
                Button("Try Again") {
                    Task { await model.loadDirectory(model.requestedDirectoryPath) }
                }
                .frame(minWidth: 44, minHeight: 44)
            }
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
                .refreshable { await model.loadDirectory(model.requestedDirectoryPath) }
            }
        } else {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    @ViewBuilder private func entryRow(_ entry: DirectoryEntry) -> some View {
        if entry.isDirectory {
            Button {
                Task { await model.loadDirectory(entry.path) }
            } label: {
                entryLabel(entry)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Folder, \(entry.name)")
        } else {
            entryLabel(entry)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(fileAccessibilityLabel(entry))
        }
    }

    private func fileAccessibilityLabel(_ entry: DirectoryEntry) -> String {
        guard let size = entry.size else { return "File, \(entry.name)" }
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        return "File, \(entry.name), \(formatted)"
    }

    private func entryLabel(_ entry: DirectoryEntry) -> some View {
        HStack(spacing: 14) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 18))
                .foregroundStyle(entry.isDirectory ? Color.primary : Color.secondary)
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

    private var requestedParent: String? {
        let path = model.requestedDirectoryPath
        guard !path.isEmpty else { return nil }
        let parts = path.split(separator: "/")
        return parts.dropLast().joined(separator: "/")
    }

    private var displayPath: String {
        let path = model.requestedDirectoryPath
        return path.isEmpty ? "/WHOX OS" : "/WHOX OS/" + path
    }
}
