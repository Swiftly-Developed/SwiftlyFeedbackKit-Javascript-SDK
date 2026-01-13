import SwiftUI

struct AsanaSettingsView: View {
    let project: Project
    @Bindable var viewModel: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var token: String
    @State private var workspaceId: String
    @State private var workspaceName: String
    @State private var asanaProjectId: String
    @State private var asanaProjectName: String
    @State private var sectionId: String
    @State private var sectionName: String
    @State private var syncStatus: Bool
    @State private var syncComments: Bool
    @State private var statusFieldId: String
    @State private var votesFieldId: String
    @State private var isActive: Bool
    @State private var showingTokenInfo = false

    // Workspace, project, section, and field selection state
    @State private var workspaces: [AsanaWorkspace] = []
    @State private var asanaProjects: [AsanaProject] = []
    @State private var sections: [AsanaSection] = []
    @State private var customFields: [AsanaCustomField] = []
    @State private var selectedWorkspace: AsanaWorkspace?
    @State private var selectedAsanaProject: AsanaProject?
    @State private var selectedSection: AsanaSection?
    @State private var selectedStatusField: AsanaCustomField?
    @State private var selectedVotesField: AsanaCustomField?

    @State private var isLoadingWorkspaces = false
    @State private var isLoadingProjects = false
    @State private var isLoadingSections = false
    @State private var isLoadingFields = false
    @State private var workspacesError: String?
    @State private var showPaywall = false

    init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
        _token = State(initialValue: project.asanaToken ?? "")
        _workspaceId = State(initialValue: project.asanaWorkspaceId ?? "")
        _workspaceName = State(initialValue: project.asanaWorkspaceName ?? "")
        _asanaProjectId = State(initialValue: project.asanaProjectId ?? "")
        _asanaProjectName = State(initialValue: project.asanaProjectName ?? "")
        _sectionId = State(initialValue: project.asanaSectionId ?? "")
        _sectionName = State(initialValue: project.asanaSectionName ?? "")
        _syncStatus = State(initialValue: project.asanaSyncStatus)
        _syncComments = State(initialValue: project.asanaSyncComments)
        _statusFieldId = State(initialValue: project.asanaStatusFieldId ?? "")
        _votesFieldId = State(initialValue: project.asanaVotesFieldId ?? "")
        _isActive = State(initialValue: project.asanaIsActive)
    }

    private var hasChanges: Bool {
        token != (project.asanaToken ?? "") ||
        workspaceId != (project.asanaWorkspaceId ?? "") ||
        workspaceName != (project.asanaWorkspaceName ?? "") ||
        asanaProjectId != (project.asanaProjectId ?? "") ||
        asanaProjectName != (project.asanaProjectName ?? "") ||
        sectionId != (project.asanaSectionId ?? "") ||
        sectionName != (project.asanaSectionName ?? "") ||
        syncStatus != project.asanaSyncStatus ||
        syncComments != project.asanaSyncComments ||
        statusFieldId != (project.asanaStatusFieldId ?? "") ||
        votesFieldId != (project.asanaVotesFieldId ?? "") ||
        isActive != project.asanaIsActive
    }

    private var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !asanaProjectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasToken: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if isConfigured {
                    Section {
                        Toggle("Integration Active", isOn: $isActive)
                    } footer: {
                        Text("When disabled, Asana sync will be paused.")
                    }
                }

                Section {
                    SecureField("Personal Access Token", text: $token)
                        .onChange(of: token) { _, newValue in
                            if !newValue.isEmpty && workspaces.isEmpty {
                                loadWorkspaces()
                            }
                        }

                    Button {
                        showingTokenInfo = true
                    } label: {
                        Label("How to get your token", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Create a personal access token at app.asana.com/0/my-apps with read/write permissions.")
                }

                if hasToken {
                    Section {
                        if isLoadingWorkspaces {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading workspaces...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let error = workspacesError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                            Button("Retry") {
                                loadWorkspaces()
                            }
                        } else {
                            Picker("Workspace", selection: $selectedWorkspace) {
                                Text("Select Workspace").tag(nil as AsanaWorkspace?)
                                ForEach(workspaces) { workspace in
                                    Text(workspace.name).tag(workspace as AsanaWorkspace?)
                                }
                            }
                            .onChange(of: selectedWorkspace) { _, newValue in
                                if let workspace = newValue {
                                    workspaceId = workspace.gid
                                    workspaceName = workspace.name
                                    loadAsanaProjects(workspaceId: workspace.gid)
                                } else {
                                    workspaceId = ""
                                    workspaceName = ""
                                    asanaProjects = []
                                    selectedAsanaProject = nil
                                    asanaProjectId = ""
                                    asanaProjectName = ""
                                    sections = []
                                    selectedSection = nil
                                    customFields = []
                                }
                            }
                        }
                    } header: {
                        Text("Workspace")
                    } footer: {
                        if !workspaceId.isEmpty {
                            Text("Selected: \(workspaceName)")
                        } else {
                            Text("Select the Asana workspace to use.")
                        }
                    }
                }

                if !workspaceId.isEmpty {
                    Section {
                        if isLoadingProjects {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading projects...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Project", selection: $selectedAsanaProject) {
                                Text("Select Project").tag(nil as AsanaProject?)
                                ForEach(asanaProjects) { asanaProject in
                                    Text(asanaProject.name).tag(asanaProject as AsanaProject?)
                                }
                            }
                            .onChange(of: selectedAsanaProject) { _, newValue in
                                if let asanaProject = newValue {
                                    asanaProjectId = asanaProject.gid
                                    asanaProjectName = asanaProject.name
                                    // Save workspace and project first, then load sections and fields
                                    saveWorkspaceAndProject {
                                        loadSections(asanaProjectId: asanaProject.gid)
                                        loadCustomFields(asanaProjectId: asanaProject.gid)
                                    }
                                } else {
                                    asanaProjectId = ""
                                    asanaProjectName = ""
                                    sections = []
                                    selectedSection = nil
                                    customFields = []
                                }
                            }
                        }
                    } header: {
                        Text("Target Project")
                    } footer: {
                        if !asanaProjectId.isEmpty {
                            Text("Selected: \(asanaProjectName)")
                        } else {
                            Text("Select the project where tasks will be created.")
                        }
                    }
                }

                if !asanaProjectId.isEmpty {
                    Section {
                        if isLoadingSections {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading sections...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Section", selection: $selectedSection) {
                                Text("No Section (Project Default)").tag(nil as AsanaSection?)
                                ForEach(sections) { section in
                                    Text(section.name).tag(section as AsanaSection?)
                                }
                            }
                            .onChange(of: selectedSection) { _, newValue in
                                if let section = newValue {
                                    sectionId = section.gid
                                    sectionName = section.name
                                } else {
                                    sectionId = ""
                                    sectionName = ""
                                }
                            }
                        }
                    } header: {
                        Text("Target Section (Optional)")
                    } footer: {
                        if !sectionId.isEmpty {
                            Text("Selected: \(sectionName)")
                        } else {
                            Text("Optionally select a section for new tasks.")
                        }
                    }
                }

                if isConfigured && !customFields.isEmpty {
                    Section {
                        customFieldPicker(
                            label: "Status Field",
                            selection: $statusFieldId,
                            allowedTypes: ["enum"]
                        )
                        customFieldPicker(
                            label: "Votes Field",
                            selection: $votesFieldId,
                            allowedTypes: ["number"]
                        )
                    } header: {
                        Text("Custom Fields (Optional)")
                    } footer: {
                        Text("Map feedback data to custom fields in Asana.")
                    }

                    Section {
                        Toggle("Sync status changes", isOn: $syncStatus)
                            .disabled(statusFieldId.isEmpty)
                        Toggle("Sync comments", isOn: $syncComments)
                    } header: {
                        Text("Sync Options")
                    } footer: {
                        if statusFieldId.isEmpty && syncStatus {
                            Text("Select a Status Field above to enable status sync.")
                                .foregroundStyle(.orange)
                        }
                    }
                } else if isConfigured && isLoadingFields {
                    Section {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading custom fields...")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Custom Fields")
                    }
                }

                if isConfigured {
                    Section {
                        Button(role: .destructive) {
                            clearIntegration()
                        } label: {
                            Label("Remove Asana Integration", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Asana Integration")
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
            .alert("Get Your Asana Access Token", isPresented: $showingTokenInfo) {
                Button("Open Asana Developer Console") {
                    if let url = URL(string: "https://app.asana.com/0/my-apps") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Go to app.asana.com/0/my-apps\n2. Create a new personal access token\n3. Copy and paste the token here")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(requiredTier: .pro)
            }
            .task {
                if hasToken {
                    loadWorkspaces()
                }
            }
        }
    }

    @ViewBuilder
    private func customFieldPicker(
        label: String,
        selection: Binding<String>,
        allowedTypes: [String]
    ) -> some View {
        let filteredFields = customFields.filter { allowedTypes.contains($0.type) }
        Picker(label, selection: selection) {
            Text("None").tag("")
            ForEach(filteredFields) { field in
                Text("\(field.name)").tag(field.gid)
            }
        }
    }

    private func loadWorkspaces() {
        guard hasToken else { return }

        isLoadingWorkspaces = true
        workspacesError = nil

        Task {
            // First save the token so the API can use it
            let result = await viewModel.updateAsanaSettings(
                projectId: project.id,
                asanaToken: token.trimmingCharacters(in: .whitespacesAndNewlines),
                asanaWorkspaceId: nil,
                asanaWorkspaceName: nil,
                asanaProjectId: nil,
                asanaProjectName: nil,
                asanaSectionId: nil,
                asanaSectionName: nil,
                asanaSyncStatus: nil,
                asanaSyncComments: nil,
                asanaStatusFieldId: nil,
                asanaVotesFieldId: nil,
                asanaIsActive: nil
            )

            if result == .success {
                workspaces = await viewModel.loadAsanaWorkspaces(projectId: project.id)
                if workspaces.isEmpty {
                    workspacesError = "No workspaces found. Make sure your token is valid."
                } else {
                    // Pre-select if workspaceId is already set
                    if !workspaceId.isEmpty {
                        selectedWorkspace = workspaces.first { $0.gid == workspaceId }
                        if selectedWorkspace != nil {
                            loadAsanaProjects(workspaceId: workspaceId)
                        }
                    }
                }
            } else if result == .paymentRequired {
                showPaywall = true
            } else {
                workspacesError = viewModel.errorMessage ?? "Failed to verify token"
            }

            isLoadingWorkspaces = false
        }
    }

    private func loadAsanaProjects(workspaceId: String) {
        isLoadingProjects = true
        Task {
            asanaProjects = await viewModel.loadAsanaProjects(projectId: project.id, workspaceId: workspaceId)

            // Pre-select if asanaProjectId is already set
            if !asanaProjectId.isEmpty {
                selectedAsanaProject = asanaProjects.first { $0.gid == asanaProjectId }
                if selectedAsanaProject != nil {
                    saveWorkspaceAndProject {
                        loadSections(asanaProjectId: asanaProjectId)
                        loadCustomFields(asanaProjectId: asanaProjectId)
                    }
                }
            }

            isLoadingProjects = false
        }
    }

    private func saveWorkspaceAndProject(completion: @escaping () -> Void) {
        Task {
            let result = await viewModel.updateAsanaSettings(
                projectId: project.id,
                asanaToken: nil,
                asanaWorkspaceId: workspaceId,
                asanaWorkspaceName: workspaceName,
                asanaProjectId: asanaProjectId,
                asanaProjectName: asanaProjectName,
                asanaSectionId: nil,
                asanaSectionName: nil,
                asanaSyncStatus: nil,
                asanaSyncComments: nil,
                asanaStatusFieldId: nil,
                asanaVotesFieldId: nil,
                asanaIsActive: nil
            )
            if result == .success {
                completion()
            }
        }
    }

    private func loadSections(asanaProjectId: String) {
        isLoadingSections = true
        Task {
            sections = await viewModel.loadAsanaSections(projectId: project.id, asanaProjectId: asanaProjectId)

            // Pre-select if sectionId is already set
            if !sectionId.isEmpty {
                selectedSection = sections.first { $0.gid == sectionId }
            }

            isLoadingSections = false
        }
    }

    private func loadCustomFields(asanaProjectId: String) {
        isLoadingFields = true
        Task {
            customFields = await viewModel.loadAsanaCustomFields(projectId: project.id, asanaProjectId: asanaProjectId)

            // Pre-select status field if already set
            if !statusFieldId.isEmpty {
                selectedStatusField = customFields.first { $0.gid == statusFieldId }
            }
            // Pre-select votes field if already set
            if !votesFieldId.isEmpty {
                selectedVotesField = customFields.first { $0.gid == votesFieldId }
            }

            isLoadingFields = false
        }
    }

    private func clearIntegration() {
        token = ""
        workspaceId = ""
        workspaceName = ""
        asanaProjectId = ""
        asanaProjectName = ""
        sectionId = ""
        sectionName = ""
        syncStatus = false
        syncComments = false
        statusFieldId = ""
        votesFieldId = ""
        selectedWorkspace = nil
        selectedAsanaProject = nil
        selectedSection = nil
        workspaces = []
        asanaProjects = []
        sections = []
        customFields = []
    }

    private func saveSettings() {
        Task {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

            let result = await viewModel.updateAsanaSettings(
                projectId: project.id,
                asanaToken: trimmedToken.isEmpty ? "" : trimmedToken,
                asanaWorkspaceId: workspaceId.isEmpty ? "" : workspaceId,
                asanaWorkspaceName: workspaceName.isEmpty ? "" : workspaceName,
                asanaProjectId: asanaProjectId.isEmpty ? "" : asanaProjectId,
                asanaProjectName: asanaProjectName.isEmpty ? "" : asanaProjectName,
                asanaSectionId: sectionId.isEmpty ? "" : sectionId,
                asanaSectionName: sectionName.isEmpty ? "" : sectionName,
                asanaSyncStatus: syncStatus,
                asanaSyncComments: syncComments,
                asanaStatusFieldId: statusFieldId.isEmpty ? "" : statusFieldId,
                asanaVotesFieldId: votesFieldId.isEmpty ? "" : votesFieldId,
                asanaIsActive: isActive
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

#Preview {
    AsanaSettingsView(
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
            allowedStatuses: ["pending", "approved", "in_progress", "completed", "rejected"]
        ),
        viewModel: ProjectViewModel()
    )
}
