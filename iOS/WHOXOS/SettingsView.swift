import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

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

            Section("Relay") {
                LabeledContent("Endpoint", value: "mobile-api.whox.ai")
                LabeledContent("Status", value: relayStatus)
                Button("Refresh connection") { Task { await model.refreshSessions() } }
                Text("Your rotating refresh token stays in the device-only Keychain. Server credentials are never stored in the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            "Disconnected"
        case .connecting:
            "Connecting"
        case .connected:
            "Connected"
        case .failed:
            "Connection failed"
        }
    }
}
