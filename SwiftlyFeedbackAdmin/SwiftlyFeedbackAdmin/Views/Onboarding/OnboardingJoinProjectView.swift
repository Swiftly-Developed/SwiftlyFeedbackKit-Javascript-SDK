import SwiftUI

struct OnboardingJoinProjectView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onBack: () -> Void

    @FocusState private var isCodeFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: platformSpacing) {
                    Spacer(minLength: 16)

                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: iconBackgroundSize, height: iconBackgroundSize)

                            Image(systemName: "person.badge.plus")
                                .font(.system(size: iconSize))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .accessibilityHidden(true)
                        }

                        VStack(spacing: 4) {
                            Text("Join a Project")
                                .font(titleFont)
                                .fontWeight(.bold)
                                .accessibilityAddTraits(.isHeader)

                            Text("Enter the invite code you received from your team")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.bottom, 8)

                    // Code Input
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Invite Code")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)

                        TextField("Enter 8-character code", text: $viewModel.inviteCode)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .focused($isCodeFocused)
                            .multilineTextAlignment(.center)
                            .font(.system(.title2, design: .monospaced))
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            .keyboardType(.asciiCapable)
                            #endif
                            .onChange(of: viewModel.inviteCode) { _, newValue in
                                // Limit to 8 characters and uppercase
                                let filtered = String(newValue.uppercased().prefix(8))
                                if filtered != newValue {
                                    viewModel.inviteCode = filtered
                                }

                                // Clear preview if code changes
                                if viewModel.invitePreview != nil && newValue.count < 8 {
                                    viewModel.clearInvitePreview()
                                }
                            }
                            .onSubmit {
                                if viewModel.inviteCode.count == 8 && viewModel.invitePreview == nil {
                                    Task { await viewModel.previewInvite() }
                                } else if viewModel.invitePreview != nil {
                                    Task { await viewModel.acceptInvite() }
                                }
                            }
                            .submitLabel(viewModel.invitePreview != nil ? .go : .continue)
                            .accessibilityLabel("Invite code input")
                            .accessibilityHint("Enter the 8-character invite code from your email")

                        // Code format helper
                        HStack {
                            Spacer()
                            Text("\(viewModel.inviteCode.count)/8 characters")
                                .font(.caption)
                                .foregroundStyle(viewModel.inviteCode.count == 8 ? .green : .secondary)
                            Spacer()
                        }
                        .accessibilityHidden(true)

                        Text("You'll find this code in your invitation email")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Verify Button (if no preview yet)
                    if viewModel.invitePreview == nil {
                        Button {
                            Task {
                                await viewModel.previewInvite()
                            }
                        } label: {
                            if viewModel.isLoading {
                                ProgressView()
                                    .frame(maxWidth: buttonMaxWidth)
                                    .frame(minHeight: 44)
                            } else {
                                Text("Verify Code")
                                    .font(.headline)
                                    .frame(maxWidth: buttonMaxWidth)
                                    .frame(minHeight: 44)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(viewModel.inviteCode.count != 8 || viewModel.isLoading)
                        .accessibilityHint(viewModel.inviteCode.count == 8 ? "Verify the invite code" : "Enter all 8 characters first")
                    }

                    // Invite Preview
                    if let preview = viewModel.invitePreview {
                        InvitePreviewCard(preview: preview, isCompact: isCompactWidth)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                        Button {
                            Task {
                                await viewModel.acceptInvite()
                            }
                        } label: {
                            if viewModel.isLoading {
                                ProgressView()
                                    .frame(maxWidth: buttonMaxWidth)
                                    .frame(minHeight: 44)
                            } else {
                                Text("Accept Invitation")
                                    .font(.headline)
                                    .frame(maxWidth: buttonMaxWidth)
                                    .frame(minHeight: 44)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!preview.emailMatches || viewModel.isLoading)
                        .accessibilityHint(preview.emailMatches ? "Accept and join the project" : "Email doesn't match the invitation")
                    }

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
            }

            // Fixed bottom button
            VStack(spacing: 12) {
                Button {
                    viewModel.clearInvitePreview()
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .accessibilityLabel("Go back to project choice")
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
            .background(bottomBackground)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.invitePreview != nil)
        .onAppear {
            #if os(iOS)
            isCodeFocused = true
            #endif
        }
    }

    // MARK: - Platform-Adaptive Properties

    private var isCompactWidth: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    private var iconBackgroundSize: CGFloat {
        #if os(macOS)
        return 80
        #else
        return isCompactWidth ? 80 : 100
        #endif
    }

    private var iconSize: CGFloat {
        #if os(macOS)
        return 36
        #else
        return isCompactWidth ? 36 : 44
        #endif
    }

    private var titleFont: Font {
        #if os(macOS)
        return .title
        #else
        return isCompactWidth ? .title2 : .title
        #endif
    }

    private var platformSpacing: CGFloat {
        #if os(macOS)
        return 24
        #else
        return isCompactWidth ? 20 : 24
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(macOS)
        return 40
        #else
        return isCompactWidth ? 24 : 40
        #endif
    }

    private var maxContentWidth: CGFloat {
        #if os(macOS)
        return 420
        #else
        return isCompactWidth ? .infinity : 480
        #endif
    }

    private var buttonMaxWidth: CGFloat {
        #if os(macOS)
        return 280
        #else
        return isCompactWidth ? .infinity : 320
        #endif
    }

    private var bottomPadding: CGFloat {
        #if os(macOS)
        return 20
        #else
        return isCompactWidth ? 12 : 20
        #endif
    }

    private var bottomBackground: some ShapeStyle {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemGroupedBackground)
        #endif
    }
}

// MARK: - Invite Preview Card

private struct InvitePreviewCard: View {
    let preview: InvitePreview
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Invitation Found")
                    .font(.headline)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Invitation found")

            Divider()

            // Details
            VStack(spacing: 12) {
                DetailRow(label: "Project", value: preview.projectName)

                if let description = preview.projectDescription, !description.isEmpty {
                    DetailRow(label: "Description", value: description)
                }

                DetailRow(label: "Invited By", value: preview.invitedByName)

                HStack {
                    Text("Your Role")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(preview.role.displayName)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(roleColor(preview.role).opacity(0.15))
                        .foregroundStyle(roleColor(preview.role))
                        .clipShape(Capsule())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Your role: \(preview.role.displayName)")

                HStack {
                    Text("Expires")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(preview.expiresAt, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Expires in \(preview.expiresAt, style: .relative)")
            }

            // Email Warning
            if !preview.emailMatches {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Email Mismatch")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("This invite was sent to \(preview.inviteEmail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Warning: Email mismatch. This invite was sent to \(preview.inviteEmail)")
            }
        }
        .padding(isCompact ? 16 : 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    private var backgroundFill: some ShapeStyle {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    private func roleColor(_ role: ProjectRole) -> Color {
        switch role {
        case .admin: return .purple
        case .member: return .blue
        case .viewer: return .gray
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

#Preview("iPhone") {
    OnboardingJoinProjectView(
        viewModel: OnboardingViewModel(
            authViewModel: AuthViewModel(),
            projectViewModel: ProjectViewModel()
        ),
        onBack: {}
    )
}

#Preview("iPad") {
    OnboardingJoinProjectView(
        viewModel: OnboardingViewModel(
            authViewModel: AuthViewModel(),
            projectViewModel: ProjectViewModel()
        ),
        onBack: {}
    )
}
