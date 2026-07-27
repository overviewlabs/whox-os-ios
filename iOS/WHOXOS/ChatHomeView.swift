import SwiftUI

struct ChatHomeView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        ZStack {
            WHOXTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                connectionBanner
                Spacer()
                emptyState
                Spacer()
                composer
            }
        }
        .navigationTitle("WHOX OS")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {}) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New conversation")
                .disabled(model.connection == .unpaired)
            }
        }
    }

    private var connectionBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.connection == .unpaired ? .orange : .green)
                .frame(width: 8, height: 8)
            Text(model.connection == .unpaired ? "Pair this iPhone to begin" : "Connected")
                .font(.footnote.weight(.medium))
            Spacer()
            if model.connection == .unpaired {
                NavigationLink("Pair", destination: SettingsView())
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(WHOXTheme.panel)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(WHOXTheme.accent.opacity(0.14)).frame(width: 88, height: 88)
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(WHOXTheme.accent)
            }
            Text("Control your WHOX OS")
                .font(.title2.bold())
            Text("Ask it to research, build, schedule, inspect, or operate your connected systems. High-impact actions always require your approval.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: {}) {
                Image(systemName: "plus")
                    .frame(width: 32, height: 32)
                    .background(WHOXTheme.panel, in: Circle())
            }
            .accessibilityLabel("Attach")

            TextField("Message WHOX OS", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(WHOXTheme.panel, in: RoundedRectangle(cornerRadius: 20))

            Button(action: send) {
                Image(systemName: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "waveform" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(WHOXTheme.accent, in: Circle())
            }
            .disabled(model.connection == .unpaired)
            .accessibilityLabel("Send message")
        }
        .padding(12)
    }

    private func send() {
        guard model.connection != .unpaired else { return }
        draft = ""
    }
}
