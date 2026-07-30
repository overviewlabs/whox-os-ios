import SwiftUI

struct ContactDetailsView: View {
    @Environment(MessageStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let conversationID: Conversation.ID

    private var conversation: Conversation? {
        store.conversation(conversationID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                actionButtons
                    .padding(.top, 17)
                phoneCard
                    .padding(.top, 20)
                contactActions
                    .padding(.top, 20)
                hideAlerts
                    .padding(.top, 20)
                blockContact
                    .padding(.top, 20)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(SmoothPressButtonStyle())
            .platformGlass(in: Circle())
            .accessibilityLabel("Back")

            VStack(spacing: 12) {
                ContactAvatar(initials: conversation?.initials ?? "—", size: 80)
                Text(conversation?.name ?? "Unknown")
                    .font(.title2.weight(.bold))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 7)
    }

    private var actionButtons: some View {
        HStack(spacing: 20) {
            contactAction(icon: "phone.fill", label: "Call", enabled: true)
            contactAction(icon: "video.fill", label: "Video", enabled: false)
            contactAction(icon: "envelope.fill", label: "Mail", enabled: false)
        }
    }

    private func contactAction(icon: String, label: String, enabled: Bool) -> some View {
        Button {} label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.45))
                .frame(width: 48, height: 48)
                .background(Color(uiColor: .systemGray6), in: Circle())
        }
        .buttonStyle(SmoothPressButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var phoneCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("phone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("RECENT")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: .systemGray3), in: RoundedRectangle(cornerRadius: 2))
            }
            Text(conversation?.name ?? "")
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .frame(height: 70)
        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var contactActions: some View {
        VStack(spacing: 0) {
            contactRow("Create New Contact")
            Divider().padding(.leading, 16)
            contactRow("Add to Existing Contact")
        }
        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func contactRow(_ title: String) -> some View {
        Button {} label: {
            Text(title)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(SmoothPressButtonStyle())
    }

    private var hideAlerts: some View {
        Toggle("Hide Alerts", isOn: Binding(
            get: { conversation?.isMuted ?? false },
            set: { _ in
                withAnimation(.whoxSmooth) {
                    store.toggleMuted(conversationID)
                }
            }
        ))
        .font(.body)
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var blockContact: some View {
        Button {} label: {
            Text("Block Contact")
                .font(.body)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(SmoothPressButtonStyle())
        .background(Color(uiColor: .systemGray6), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
