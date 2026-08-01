import SwiftUI

/// Sign in to a Happiest Baby account. The password is handed to the API
/// client for the login call and never persisted (§5). Errors surface inline —
/// this is the one SNOO surface allowed to show a network error (§9).
struct SnooLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var coordinator = SnooSyncCoordinator.shared

    @State private var email: String
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    /// Pre-fill the email for the needs-reauth path (§5).
    init(prefilledEmail: String = "") {
        _email = State(initialValue: prefilledEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Happiest Baby account")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(AppColor.urgencyRed)
                        }
                        Text("Uses the same sign-in as the SNOO app. Your password is only used to connect and is never stored. \(SnooFeature.disclaimer)")
                    }
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Text("Connect")
                            if isConnecting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!canConnect)
                }
            }
            .navigationTitle("Connect SNOO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isConnecting)
        }
    }

    private var canConnect: Bool {
        !isConnecting
            && email.contains("@")
            && !password.isEmpty
    }

    private func connect() {
        errorMessage = nil
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                try await coordinator.signIn(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    context: context
                )
                Haptics.success()
                dismiss()
            } catch let error as SnooAPIError {
                errorMessage = error.userMessage
            } catch {
                errorMessage = "Something went wrong. Try again."
            }
        }
    }
}
