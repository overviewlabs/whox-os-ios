import SwiftUI

struct GatewaySetupView: View {
    @Environment(GatewayConfiguration.self) private var configuration
    @Environment(\.dismiss) private var dismiss
    @State private var gatewayURL = ""
    @State private var apiKey = ""
    @State private var loadedSavedValues = false
    let onConnect: () async -> Void
    let onDisconnect: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://gateway.example.com", text: $gatewayURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("API server key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Hermes Gateway")
                } footer: {
                    Text("Use the public HTTPS address for your Hermes API server. Profile routes such as /p/work are supported.")
                }

                if let error = configuration.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Text(configuration.isConfigured ? "Reconnect and Sync" : "Connect and Sync")
                            Spacer()
                            if configuration.isConnecting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(
                        configuration.isConnecting
                            || gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if configuration.isConfigured {
                    Section {
                        Button("Disconnect Gateway", role: .destructive) {
                            withAnimation(.whoxSmooth) {
                                configuration.disconnect()
                                onDisconnect()
                            }
                        }
                    }
                }

                Section {
                    Label("The API key is stored in this device’s Keychain and is never written to app preferences.", systemImage: "lock.shield")
                    Label("A Hermes API key can run agent tools, including terminal commands. Only connect to a gateway you trust.", systemImage: "exclamationmark.shield")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Connect Hermes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if configuration.isConfigured {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .animation(.whoxSmooth, value: configuration.errorMessage)
            .task {
                guard !loadedSavedValues else { return }
                gatewayURL = configuration.gatewayURL
                apiKey = configuration.apiKey
                loadedSavedValues = true
            }
        }
        .interactiveDismissDisabled(!configuration.isConfigured || configuration.isConnecting)
    }

    private func connect() {
        configuration.isConnecting = true
        configuration.errorMessage = nil
        Task {
            defer { configuration.isConnecting = false }
            do {
                try configuration.save(url: gatewayURL, key: apiKey)
                await onConnect()
            } catch {
                configuration.errorMessage = error.localizedDescription
            }
        }
    }
}
