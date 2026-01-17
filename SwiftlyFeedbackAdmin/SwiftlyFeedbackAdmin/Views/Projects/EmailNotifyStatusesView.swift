import SwiftUI

struct EmailNotifyStatusesView: View {
    let project: Project
    @Bindable var viewModel: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var enabledStatuses: Set<FeedbackStatus>
    @State private var showPaywall = false

    init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
        // Initialize with the project's email notify statuses
        let statusSet = Set(project.emailNotifyStatuses.compactMap { FeedbackStatus(rawValue: $0) })
        _enabledStatuses = State(initialValue: statusSet)
    }

    private var hasChanges: Bool {
        let currentStatuses = Set(project.emailNotifyStatuses.compactMap { FeedbackStatus(rawValue: $0) })
        return enabledStatuses != currentStatuses
    }

    /// Only show statuses that are allowed in this project (excluding pending - initial state)
    private var availableStatuses: [FeedbackStatus] {
        project.allowedStatuses
            .compactMap { FeedbackStatus(rawValue: $0) }
            .filter { $0 != .pending }  // Pending is initial state, rarely needs notification
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose which status changes trigger email notifications to feedback submitters and voters who opted in.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Notify when status changes to") {
                    ForEach(availableStatuses, id: \.self) { status in
                        Toggle(isOn: binding(for: status)) {
                            StatusRow(status: status)
                        }
                        .tint(statusColor(for: status))
                    }
                }

                Section {
                    Button("Enable All") {
                        enabledStatuses = Set(availableStatuses)
                    }
                    .disabled(enabledStatuses == Set(availableStatuses))

                    Button("Disable All") {
                        enabledStatuses = []
                    }
                    .disabled(enabledStatuses.isEmpty)

                    Button("Final States Only") {
                        enabledStatuses = Set([.completed, .rejected].filter { availableStatuses.contains($0) })
                    }
                } footer: {
                    Text("Final states: Completed and Rejected")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Email Notifications")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges || viewModel.isLoading)
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
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(requiredTier: .pro)
            }
        }
    }

    private func binding(for status: FeedbackStatus) -> Binding<Bool> {
        Binding(
            get: { enabledStatuses.contains(status) },
            set: { isEnabled in
                if isEnabled {
                    enabledStatuses.insert(status)
                } else {
                    enabledStatuses.remove(status)
                }
            }
        )
    }

    private func statusColor(for status: FeedbackStatus) -> Color {
        switch status.color {
        case "gray": return .gray
        case "blue": return .blue
        case "orange": return .orange
        case "cyan": return .cyan
        case "green": return .green
        case "red": return .red
        default: return .primary
        }
    }

    private func saveSettings() {
        Task {
            let statusStrings = enabledStatuses.map { $0.rawValue }
            let result = await viewModel.updateEmailNotifyStatuses(
                projectId: project.id,
                emailNotifyStatuses: statusStrings
            )
            switch result {
            case .success:
                dismiss()
            case .paymentRequired:
                showPaywall = true
            case .otherError:
                break
            }
        }
    }
}

// MARK: - Status Row

private struct StatusRow: View {
    let status: FeedbackStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: status.icon)
                .foregroundStyle(statusColor)
                .frame(width: 24)
            Text(status.displayName)
        }
    }

    private var statusColor: Color {
        switch status.color {
        case "gray": return .gray
        case "blue": return .blue
        case "orange": return .orange
        case "cyan": return .cyan
        case "green": return .green
        case "red": return .red
        default: return .primary
        }
    }
}

#Preview {
    EmailNotifyStatusesView(
        project: Project(
            id: UUID(),
            name: "Test Project",
            apiKey: "test-api-key",
            description: "A test description",
            ownerId: UUID(),
            ownerEmail: "test@example.com",
            isArchived: false,
            archivedAt: nil,
            colorIndex: 0,
            feedbackCount: 42,
            memberCount: 5,
            createdAt: Date(),
            updatedAt: Date(),
            slackWebhookUrl: nil,
            slackNotifyNewFeedback: true,
            slackNotifyNewComments: true,
            slackNotifyStatusChanges: true,
            allowedStatuses: ["pending", "approved", "in_progress", "completed", "rejected"],
            emailNotifyStatuses: ["approved", "in_progress", "completed", "rejected"]
        ),
        viewModel: ProjectViewModel()
    )
}
