import SwiftUI

struct AcceptInviteView: View {
    @Bindable var viewModel: ProjectViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite Code", text: $viewModel.inviteCode)
                        .focused($isCodeFocused)
                        .textCase(.uppercase)
                        .font(.system(.title2, design: .monospaced))
                        .multilineTextAlignment(.center)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        .keyboardType(.asciiCapable)
                        #endif
                } header: {
                    Text("Enter Invite Code")
                } footer: {
                    Text("Enter the 8-character code you received in your invitation email.")
                }

                if let preview = viewModel.invitePreview {
                    Section("Invitation Details") {
                        LabeledContent("Project") {
                            Text(preview.projectName)
                                .fontWeight(.medium)
                        }

                        if let description = preview.projectDescription, !description.isEmpty {
                            LabeledContent("Description") {
                                Text(description)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        LabeledContent("Invited By") {
                            Text(preview.invitedByName)
                        }

                        LabeledContent("Your Role") {
                            Text(preview.role.displayName)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(roleColor(preview.role).opacity(0.15))
                                .foregroundStyle(roleColor(preview.role))
                                .clipShape(Capsule())
                        }

                        LabeledContent("Expires") {
                            Text(preview.expiresAt, style: .relative)
                                .foregroundStyle(.secondary)
                        }

                        if !preview.emailMatches {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Email Mismatch")
                                        .fontWeight(.medium)
                                    Text("This invite was sent to \(preview.inviteEmail)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            Task {
                                if await viewModel.acceptInviteCode() {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Accept Invitation")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(!preview.emailMatches || viewModel.isLoading)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Join Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.clearInviteFields()
                        dismiss()
                    }
                }

                if viewModel.invitePreview == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Verify") {
                            Task {
                                await viewModel.previewInviteCode()
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(viewModel.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isLoading)
            .overlay {
                if viewModel.isLoading {
                    Color.black.opacity(0.1)
                        .ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .onAppear {
                isCodeFocused = true
            }
            .onChange(of: viewModel.inviteCode) {
                // Clear preview if code changes
                if viewModel.invitePreview != nil {
                    viewModel.invitePreview = nil
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .alert("Success", isPresented: $viewModel.showSuccess) {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(viewModel.successMessage ?? "")
            }
        }
    }

    private func roleColor(_ role: ProjectRole) -> Color {
        switch role {
        case .admin: return .purple
        case .member: return .blue
        case .viewer: return .gray
        }
    }
}

#Preview {
    AcceptInviteView(viewModel: ProjectViewModel())
}
