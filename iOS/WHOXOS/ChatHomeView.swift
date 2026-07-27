import SwiftUI

struct ChatHomeView: View {
    @Environment(AppModel.self) private var model
    let onOpenDrawer: () -> Void

    @State private var draft = ""

    var body: some View {
        ZStack {
            WHOXTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                quickActions
                composer
            }
            .padding(.top, -7)
            .padding(.bottom, 16)
        }
    }

    private var topBar: some View {
        HStack {
            chromeButton(action: onOpenDrawer, label: "Open navigation") {
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().frame(width: 17, height: 2)
                    Capsule().frame(width: 11, height: 2)
                }
            }

            Spacer()

            chromeButton(action: {}, label: "Voice mode") {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .medium))
            }
        }
        .padding(.horizontal, 18)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 20) {
            quickAction("Create an image", systemImage: "photo")
            quickAction("Write or edit", systemImage: "pencil")
            quickAction("Look something up", systemImage: "globe")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 23)
        .padding(.bottom, 28)
    }

    private var composer: some View {
        HStack(spacing: 14) {
            Button(action: {}) {
                Image(systemName: "plus")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(WHOXTheme.primaryText)
            }
            .accessibilityLabel("Add attachment")

            TextField("Ask WHOX OS", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16))
                .foregroundStyle(WHOXTheme.primaryText)
                .tint(WHOXTheme.primaryText)

            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WHOXTheme.inverseText)
                        .frame(width: 32, height: 32)
                        .background(WHOXTheme.primaryText, in: Circle())
                }
                .accessibilityLabel("Send")
            } else {
                Image(systemName: "mic")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WHOXTheme.primaryText)

                Button(action: {}) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WHOXTheme.inverseText)
                        .frame(width: 32, height: 32)
                        .background(WHOXTheme.primaryText, in: Circle())
                }
                .accessibilityLabel("Start voice mode")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(WHOXTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(WHOXTheme.border, lineWidth: 1)
                }
        )
        .padding(.horizontal, 30)
    }

    private func quickAction(_ title: String, systemImage: String) -> some View {
        Button(action: {}) {
            HStack(spacing: 17) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 15, weight: .regular))
            }
            .foregroundStyle(WHOXTheme.primaryText)
        }
    }

    private func chromeButton<Label: View>(
        action: @escaping () -> Void,
        label: String,
        @ViewBuilder content: () -> Label
    ) -> some View {
        Button(action: action) {
            content()
                .foregroundStyle(WHOXTheme.primaryText)
                .frame(width: 44, height: 44)
                .background(WHOXTheme.surface, in: Circle())
                .overlay {
                    Circle().stroke(WHOXTheme.border, lineWidth: 1)
                }
        }
        .accessibilityLabel(label)
    }

    private func send() {
        guard model.connection != .connecting else { return }
        draft = ""
    }
}
