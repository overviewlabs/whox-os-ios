import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        @Bindable var model = model

        ZStack {
            WHOXTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 52)

                    Image("WHOXStudioLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .accessibilityLabel("WHOX")

                    VStack(spacing: 8) {
                        Text("WHOX OS")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("Members only")
                            .font(.headline)
                            .foregroundStyle(WHOXTheme.secondaryText)
                    }

                    VStack(spacing: 14) {
                        TextField("WHOX email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .modifier(LoginFieldStyle())

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(signIn)
                            .modifier(LoginFieldStyle())
                    }

                    if let error = model.authenticationError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("login-error")
                    }

                    Button(action: signIn) {
                        Group {
                            if model.isAuthenticating {
                                ProgressView()
                                    .tint(WHOXTheme.inverseText)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WHOXTheme.inverseText)
                    .background(WHOXTheme.primaryText, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .disabled(!canSubmit || model.isAuthenticating)
                    .opacity(canSubmit ? 1 : 0.45)
                    .accessibilityIdentifier("member-sign-in")

                    Text("Access is restricted to authorized WHOX members.")
                        .font(.footnote)
                        .foregroundStyle(WHOXTheme.secondaryText)
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 32)
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 28)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func signIn() {
        guard canSubmit, !model.isAuthenticating else { return }
        focusedField = nil
        Task {
            await model.signIn(email: email, password: password)
            password = ""
        }
    }
}

private struct LoginFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(WHOXTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(WHOXTheme.border, lineWidth: 1)
            }
    }
}
