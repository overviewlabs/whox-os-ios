import SwiftUI

struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Agent") {
                statusRow("Connection", value: model.connection == .unpaired ? "Not paired" : "Connected", icon: "network")
                statusRow("Active run", value: model.activeRunID == nil ? "None" : "Running", icon: "bolt.horizontal.circle")
                statusRow("Approval", value: model.pendingApproval == nil ? "None pending" : "Action required", icon: "checkmark.shield")
            }

            Section {
                ContentUnavailableView(
                    "No recent activity",
                    systemImage: "waveform.path.ecg",
                    description: Text("Tool progress and completed runs will appear here.")
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(WHOXTheme.background)
        .navigationTitle("Activity")
    }

    private func statusRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
