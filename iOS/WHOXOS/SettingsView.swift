import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var pairingCode = ""

    var body: some View {
        Form {
            Section("Account") {
                HStack(spacing: 12) {
                    Image("WHOXStudioLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.authenticatedUser?.email ?? "WHOX member")
                            .font(.body.weight(.medium))
                        Text((model.authenticatedUser?.role ?? "member").capitalized)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Sign Out", role: .destructive) {
                    Task { await model.signOut() }
                }
            }

            Section("Pair WHOX OS") {
                TextField("One-time pairing code", text: $pairingCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button(model.connection == .connecting ? "Pairing…" : "Pair this iPhone") {
                    Task { await model.pair(with: pairingCode) }
                }
                .disabled(
                    pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.connection == .connecting
                )
                Text("Generate the one-time code from your WHOX OS server. The private server key never leaves the server.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Relay") {
                LabeledContent("Endpoint", value: "mobile-api.whox.ai")
                LabeledContent("Status", value: relayStatus)
            }

            Section("About") {
                LabeledContent("App", value: "WHOX OS")
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("Bundle ID", value: "com.whox.whoxos")
            }
        }
        .scrollContentBackground(.hidden)
        .background(WHOXTheme.background)
        .navigationTitle("Settings")
    }

    private var relayStatus: String {
        switch model.connection {
        case .unpaired:
            "Not paired"
        case .connecting:
            "Pairing"
        case .connected:
            "Connected"
        case .failed:
            "Connection failed"
        }
    }
}
