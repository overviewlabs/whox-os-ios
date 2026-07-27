import SwiftUI

struct ControlCenterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                controlCard("Server", value: model.connection == .unpaired ? "Offline" : "Online", icon: "server.rack")
                controlCard("Sessions", value: "\(model.sessions.count)", icon: "bubble.left.and.bubble.right")
                controlCard("Schedules", value: "Manage", icon: "calendar.badge.clock")
                controlCard("Skills", value: "Explore", icon: "wand.and.stars")
            }
            .padding()

            VStack(alignment: .leading, spacing: 12) {
                Label("Safety", systemImage: "lock.shield.fill")
                    .font(.headline)
                Text("Terminal commands, remote writes, deployments, and other high-impact actions remain protected by WHOX OS approval gates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(WHOXTheme.panel, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)
        }
        .background(WHOXTheme.background)
        .navigationTitle("Control Center")
    }

    private func controlCard(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(WHOXTheme.accent)
            Text(title).font(.headline)
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 115, alignment: .leading)
        .padding()
        .background(WHOXTheme.panel, in: RoundedRectangle(cornerRadius: 20))
    }
}
