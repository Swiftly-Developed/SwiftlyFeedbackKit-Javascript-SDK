import SwiftUI

struct TransferOwnershipSheet: View {
    let project: Project
    let projectId: UUID
    @Bindable var viewModel: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscriptionService

    @State private var selectedMemberId: UUID?
    @State private var showingConfirmation = false
    @State private var transferMode: TransferMode = .selectMember
    @State private var emailInput: String = ""
    @State private var showingPaywall = false
    @State private var errorMessage: String?
    @State private var showingError = false

    enum TransferMode: String, CaseIterable {
        case selectMember = "Select Member"
        case enterEmail = "Enter Email"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Description section
                Section {
                    Text("Transfer ownership of this project to another user. You will be demoted to an Admin member.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Transfer mode picker
                Section {
                    Picker("Transfer To", selection: $transferMode) {
                        ForEach(TransferMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Content based on mode
                switch transferMode {
                case .selectMember:
                    memberSelectionSection
                case .enterEmail:
                    emailInputSection
                }

                // Warnings section
                warningSection
            }
            .formStyle(.grouped)
            .navigationTitle("Transfer Ownership")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer") {
                        showingConfirmation = true
                    }
                    .fontWeight(.semibold)
                    .disabled(!canTransfer)
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
            .confirmationDialog(
                "Transfer Ownership",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Transfer Ownership", role: .destructive) {
                    Task {
                        await performTransfer()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(requiredTier: .team)
            }
            .task {
                await viewModel.loadMembers(projectId: projectId)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var memberSelectionSection: some View {
        Section {
            if viewModel.projectMembers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Members")
                        .font(.headline)
                    Text("Add team members first, or enter an email address to transfer to any user.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(viewModel.projectMembers) { member in
                    MemberRow(
                        member: member,
                        isSelected: member.userId == selectedMemberId,
                        onSelect: { selectedMemberId = member.userId }
                    )
                }
            }
        } header: {
            Text("Select New Owner")
        } footer: {
            if !viewModel.projectMembers.isEmpty {
                Text("The selected member will become the project owner.")
            }
        }
    }

    @ViewBuilder
    private var emailInputSection: some View {
        Section {
            TextField("Email address", text: $emailInput)
                .textContentType(.emailAddress)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        } header: {
            Text("New Owner Email")
        } footer: {
            Text("Enter the email address of a registered Feedback Kit user. They will receive a notification.")
        }
    }

    @ViewBuilder
    private var warningSection: some View {
        Section("Important") {
            WarningRow(
                icon: "exclamationmark.triangle.fill",
                iconColor: .orange,
                title: "This action cannot be undone",
                description: "You will lose owner privileges and become an Admin member of this project."
            )

            if !viewModel.projectMembers.isEmpty {
                WarningRow(
                    icon: "person.2.fill",
                    iconColor: .blue,
                    title: "Team subscription required",
                    description: "This project has team members. The new owner must have a Team subscription."
                )
            }
        }
    }

    // MARK: - Computed Properties

    private var canTransfer: Bool {
        switch transferMode {
        case .selectMember:
            return selectedMemberId != nil && !viewModel.isLoading
        case .enterEmail:
            return isValidEmail(emailInput) && !viewModel.isLoading
        }
    }

    private var confirmationMessage: String {
        switch transferMode {
        case .selectMember:
            if let memberId = selectedMemberId,
               let member = viewModel.projectMembers.first(where: { $0.userId == memberId }) {
                return "Transfer ownership of \"\(project.name)\" to \(member.userName)? You will become an Admin member."
            }
            return "Transfer ownership?"
        case .enterEmail:
            return "Transfer ownership of \"\(project.name)\" to \(emailInput)? You will become an Admin member."
        }
    }

    // MARK: - Actions

    private func performTransfer() async {
        let result: ProjectViewModel.TransferOwnershipResult

        switch transferMode {
        case .selectMember:
            guard let memberId = selectedMemberId else { return }
            result = await viewModel.transferOwnership(projectId: projectId, toMemberId: memberId)
        case .enterEmail:
            result = await viewModel.transferOwnership(projectId: projectId, toEmail: emailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }

        switch result {
        case .success(let newOwnerName):
            viewModel.successMessage = "Ownership transferred to \(newOwnerName)"
            viewModel.showSuccess = true
            dismiss()
        case .paymentRequired:
            showingPaywall = true
        case .notFound:
            errorMessage = "User not found. Make sure they have a Feedback Kit account."
            showingError = true
        case .otherError(let message):
            errorMessage = message
            showingError = true
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return trimmed.range(of: emailRegex, options: .regularExpression) != nil
    }
}

// MARK: - Member Row

private struct MemberRow: View {
    let member: ProjectMember
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // User info
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.userName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(member.userEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Role badge
                RoleBadge(role: member.role)

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary.opacity(0.5))
                    .imageScale(.large)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Warning Row

private struct WarningRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .font(.body)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Role Badge

private struct RoleBadge: View {
    let role: ProjectRole

    var body: some View {
        Text(role.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(roleColor.opacity(0.12))
            .foregroundStyle(roleColor)
            .clipShape(Capsule())
    }

    private var roleColor: Color {
        switch role {
        case .admin: return .orange
        case .member: return .blue
        case .viewer: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    TransferOwnershipSheet(
        project: Project(
            id: UUID(),
            name: "My App",
            apiKey: "sf_test",
            description: "Test project",
            ownerId: UUID(),
            ownerEmail: "owner@example.com",
            isArchived: false,
            archivedAt: nil,
            colorIndex: 0,
            feedbackCount: 5,
            memberCount: 3,
            createdAt: Date(),
            updatedAt: Date(),
            slackWebhookUrl: nil,
            slackNotifyNewFeedback: false,
            slackNotifyNewComments: false,
            slackNotifyStatusChanges: false,
            slackIsActive: false,
            allowedStatuses: ["pending", "approved", "completed", "rejected"],
            emailNotifyStatuses: ["approved", "completed", "rejected"],
            githubOwner: nil,
            githubRepo: nil,
            githubToken: nil,
            githubDefaultLabels: nil,
            githubSyncStatus: false,
            githubIsActive: false,
            clickupToken: nil,
            clickupListId: nil,
            clickupWorkspaceName: nil,
            clickupListName: nil,
            clickupDefaultTags: nil,
            clickupSyncStatus: false,
            clickupSyncComments: false,
            clickupVotesFieldId: nil,
            clickupIsActive: false,
            notionToken: nil,
            notionDatabaseId: nil,
            notionDatabaseName: nil,
            notionSyncStatus: false,
            notionSyncComments: false,
            notionStatusProperty: nil,
            notionVotesProperty: nil,
            notionIsActive: false,
            mondayToken: nil,
            mondayBoardId: nil,
            mondayBoardName: nil,
            mondayGroupId: nil,
            mondayGroupName: nil,
            mondaySyncStatus: false,
            mondaySyncComments: false,
            mondayStatusColumnId: nil,
            mondayVotesColumnId: nil,
            mondayIsActive: false,
            linearToken: nil,
            linearTeamId: nil,
            linearTeamName: nil,
            linearProjectId: nil,
            linearProjectName: nil,
            linearDefaultLabelIds: nil,
            linearSyncStatus: false,
            linearSyncComments: false,
            linearIsActive: false,
            trelloToken: nil,
            trelloBoardId: nil,
            trelloBoardName: nil,
            trelloListId: nil,
            trelloListName: nil,
            trelloSyncStatus: false,
            trelloSyncComments: false,
            trelloIsActive: false,
            airtableToken: nil,
            airtableBaseId: nil,
            airtableBaseName: nil,
            airtableTableId: nil,
            airtableTableName: nil,
            airtableSyncStatus: false,
            airtableSyncComments: false,
            airtableStatusFieldId: nil,
            airtableVotesFieldId: nil,
            airtableTitleFieldId: nil,
            airtableDescriptionFieldId: nil,
            airtableCategoryFieldId: nil,
            airtableIsActive: false,
            asanaToken: nil,
            asanaWorkspaceId: nil,
            asanaWorkspaceName: nil,
            asanaProjectId: nil,
            asanaProjectName: nil,
            asanaSectionId: nil,
            asanaSectionName: nil,
            asanaSyncStatus: false,
            asanaSyncComments: false,
            asanaStatusFieldId: nil,
            asanaVotesFieldId: nil,
            asanaIsActive: false,
            basecampAccessToken: nil,
            basecampAccountId: nil,
            basecampAccountName: nil,
            basecampProjectId: nil,
            basecampProjectName: nil,
            basecampTodosetId: nil,
            basecampTodolistId: nil,
            basecampTodolistName: nil,
            basecampSyncStatus: false,
            basecampSyncComments: false,
            basecampIsActive: false
        ),
        projectId: UUID(),
        viewModel: ProjectViewModel()
    )
    .environment(SubscriptionService.shared)
}
