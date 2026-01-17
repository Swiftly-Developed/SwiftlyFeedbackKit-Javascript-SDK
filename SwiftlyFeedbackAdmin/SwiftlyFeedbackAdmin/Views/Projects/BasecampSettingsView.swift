import SwiftUI

struct BasecampSettingsView: View {
    let project: Project
    @Bindable var viewModel: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var accessToken: String
    @State private var accountId: String
    @State private var accountName: String
    @State private var basecampProjectId: String
    @State private var basecampProjectName: String
    @State private var todosetId: String
    @State private var todolistId: String
    @State private var todolistName: String
    @State private var syncStatus: Bool
    @State private var syncComments: Bool
    @State private var isActive: Bool
    @State private var showingTokenInfo = false

    // Account, project, and todolist selection state
    @State private var accounts: [BasecampAccount] = []
    @State private var basecampProjects: [BasecampProject] = []
    @State private var todolists: [BasecampTodolist] = []
    @State private var selectedAccount: BasecampAccount?
    @State private var selectedBasecampProject: BasecampProject?
    @State private var selectedTodolist: BasecampTodolist?

    @State private var isLoadingAccounts = false
    @State private var isLoadingProjects = false
    @State private var isLoadingTodolists = false
    @State private var accountsError: String?
    @State private var showPaywall = false

    init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
        _accessToken = State(initialValue: project.basecampAccessToken ?? "")
        _accountId = State(initialValue: project.basecampAccountId ?? "")
        _accountName = State(initialValue: project.basecampAccountName ?? "")
        _basecampProjectId = State(initialValue: project.basecampProjectId ?? "")
        _basecampProjectName = State(initialValue: project.basecampProjectName ?? "")
        _todosetId = State(initialValue: project.basecampTodosetId ?? "")
        _todolistId = State(initialValue: project.basecampTodolistId ?? "")
        _todolistName = State(initialValue: project.basecampTodolistName ?? "")
        _syncStatus = State(initialValue: project.basecampSyncStatus)
        _syncComments = State(initialValue: project.basecampSyncComments)
        _isActive = State(initialValue: project.basecampIsActive)
    }

    private var hasChanges: Bool {
        accessToken != (project.basecampAccessToken ?? "") ||
        accountId != (project.basecampAccountId ?? "") ||
        accountName != (project.basecampAccountName ?? "") ||
        basecampProjectId != (project.basecampProjectId ?? "") ||
        basecampProjectName != (project.basecampProjectName ?? "") ||
        todosetId != (project.basecampTodosetId ?? "") ||
        todolistId != (project.basecampTodolistId ?? "") ||
        todolistName != (project.basecampTodolistName ?? "") ||
        syncStatus != project.basecampSyncStatus ||
        syncComments != project.basecampSyncComments ||
        isActive != project.basecampIsActive
    }

    private var isConfigured: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !basecampProjectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !todolistId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasToken: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if isConfigured {
                    Section {
                        Toggle("Integration Active", isOn: $isActive)
                    } footer: {
                        Text("When disabled, Basecamp sync will be paused.")
                    }
                }

                Section {
                    SecureField("Access Token", text: $accessToken)
                        .onChange(of: accessToken) { _, newValue in
                            if !newValue.isEmpty && accounts.isEmpty {
                                loadAccounts()
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
                    Text("Create an OAuth2 access token or use the Basecamp API integration.")
                }

                if hasToken {
                    Section {
                        if isLoadingAccounts {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading accounts...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let error = accountsError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                            Button("Retry") {
                                loadAccounts()
                            }
                        } else {
                            Picker("Account", selection: $selectedAccount) {
                                Text("Select Account").tag(nil as BasecampAccount?)
                                ForEach(accounts) { account in
                                    Text(account.name).tag(account as BasecampAccount?)
                                }
                            }
                            .onChange(of: selectedAccount) { _, newValue in
                                if let account = newValue {
                                    accountId = String(account.id)
                                    accountName = account.name
                                    loadBasecampProjects(accountId: String(account.id))
                                } else {
                                    accountId = ""
                                    accountName = ""
                                    basecampProjects = []
                                    selectedBasecampProject = nil
                                    basecampProjectId = ""
                                    basecampProjectName = ""
                                    todosetId = ""
                                    todolists = []
                                    selectedTodolist = nil
                                    todolistId = ""
                                    todolistName = ""
                                }
                            }
                        }
                    } header: {
                        Text("Account")
                    } footer: {
                        if !accountId.isEmpty {
                            Text("Selected: \(accountName)")
                        } else {
                            Text("Select the Basecamp account to use.")
                        }
                    }
                }

                if !accountId.isEmpty {
                    Section {
                        if isLoadingProjects {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading projects...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Project", selection: $selectedBasecampProject) {
                                Text("Select Project").tag(nil as BasecampProject?)
                                ForEach(basecampProjects) { basecampProject in
                                    Text(basecampProject.name).tag(basecampProject as BasecampProject?)
                                }
                            }
                            .onChange(of: selectedBasecampProject) { _, newValue in
                                if let basecampProject = newValue {
                                    basecampProjectId = String(basecampProject.id)
                                    basecampProjectName = basecampProject.name
                                    todosetId = basecampProject.todosetId ?? ""
                                    // Save account and project first, then load todolists
                                    saveAccountAndProject {
                                        loadTodolists(accountId: accountId, basecampProjectId: String(basecampProject.id))
                                    }
                                } else {
                                    basecampProjectId = ""
                                    basecampProjectName = ""
                                    todosetId = ""
                                    todolists = []
                                    selectedTodolist = nil
                                    todolistId = ""
                                    todolistName = ""
                                }
                            }
                        }
                    } header: {
                        Text("Target Project")
                    } footer: {
                        if !basecampProjectId.isEmpty {
                            Text("Selected: \(basecampProjectName)")
                        } else {
                            Text("Select the project where to-dos will be created.")
                        }
                    }
                }

                if !basecampProjectId.isEmpty {
                    Section {
                        if isLoadingTodolists {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading to-do lists...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if todolists.isEmpty && !isLoadingTodolists {
                            Text("No to-do lists found. Make sure the project has a To-do tool enabled.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            Picker("To-do List", selection: $selectedTodolist) {
                                Text("Select To-do List").tag(nil as BasecampTodolist?)
                                ForEach(todolists) { todolist in
                                    Text(todolist.name).tag(todolist as BasecampTodolist?)
                                }
                            }
                            .onChange(of: selectedTodolist) { _, newValue in
                                if let todolist = newValue {
                                    todolistId = String(todolist.id)
                                    todolistName = todolist.name
                                } else {
                                    todolistId = ""
                                    todolistName = ""
                                }
                            }
                        }
                    } header: {
                        Text("Target To-do List")
                    } footer: {
                        if !todolistId.isEmpty {
                            Text("Selected: \(todolistName)")
                        } else {
                            Text("Select the to-do list where items will be created.")
                        }
                    }
                }

                if isConfigured {
                    Section {
                        Toggle("Sync status changes", isOn: $syncStatus)
                        Toggle("Sync comments", isOn: $syncComments)
                    } header: {
                        Text("Sync Options")
                    } footer: {
                        Text("Status sync marks to-dos as complete when feedback is completed or rejected.")
                    }

                    Section {
                        Button(role: .destructive) {
                            clearIntegration()
                        } label: {
                            Label("Remove Basecamp Integration", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Basecamp Integration")
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
            .alert("Get Your Basecamp Access Token", isPresented: $showingTokenInfo) {
                Button("Open Basecamp Integrations") {
                    if let url = URL(string: "https://launchpad.37signals.com/integrations") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Go to launchpad.37signals.com/integrations\n2. Create a new integration\n3. Copy the access token and paste it here")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(requiredTier: .pro)
            }
            .task {
                if hasToken {
                    loadAccounts()
                }
            }
        }
    }

    private func loadAccounts() {
        guard hasToken else { return }

        isLoadingAccounts = true
        accountsError = nil

        Task {
            // First save the token so the API can use it
            let result = await viewModel.updateBasecampSettings(
                projectId: project.id,
                basecampAccessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
                basecampAccountId: nil,
                basecampAccountName: nil,
                basecampProjectId: nil,
                basecampProjectName: nil,
                basecampTodosetId: nil,
                basecampTodolistId: nil,
                basecampTodolistName: nil,
                basecampSyncStatus: nil,
                basecampSyncComments: nil,
                basecampIsActive: nil
            )

            if result == .success {
                accounts = await viewModel.loadBasecampAccounts(projectId: project.id)
                if accounts.isEmpty {
                    accountsError = "No accounts found. Make sure your token is valid."
                } else {
                    // Pre-select if accountId is already set
                    if !accountId.isEmpty, let id = Int(accountId) {
                        selectedAccount = accounts.first { $0.id == id }
                        if selectedAccount != nil {
                            loadBasecampProjects(accountId: accountId)
                        }
                    }
                }
            } else if result == .paymentRequired {
                showPaywall = true
            } else {
                accountsError = viewModel.errorMessage ?? "Failed to verify token"
            }

            isLoadingAccounts = false
        }
    }

    private func loadBasecampProjects(accountId: String) {
        isLoadingProjects = true
        Task {
            basecampProjects = await viewModel.loadBasecampProjects(projectId: project.id, accountId: accountId)

            // Pre-select if basecampProjectId is already set
            if !basecampProjectId.isEmpty, let id = Int(basecampProjectId) {
                selectedBasecampProject = basecampProjects.first { $0.id == id }
                if selectedBasecampProject != nil {
                    saveAccountAndProject {
                        loadTodolists(accountId: accountId, basecampProjectId: basecampProjectId)
                    }
                }
            }

            isLoadingProjects = false
        }
    }

    private func saveAccountAndProject(completion: @escaping () -> Void) {
        Task {
            let result = await viewModel.updateBasecampSettings(
                projectId: project.id,
                basecampAccessToken: nil,
                basecampAccountId: accountId,
                basecampAccountName: accountName,
                basecampProjectId: basecampProjectId,
                basecampProjectName: basecampProjectName,
                basecampTodosetId: todosetId,
                basecampTodolistId: nil,
                basecampTodolistName: nil,
                basecampSyncStatus: nil,
                basecampSyncComments: nil,
                basecampIsActive: nil
            )
            if result == .success {
                completion()
            }
        }
    }

    private func loadTodolists(accountId: String, basecampProjectId: String) {
        isLoadingTodolists = true
        Task {
            todolists = await viewModel.loadBasecampTodolists(
                projectId: project.id,
                accountId: accountId,
                basecampProjectId: basecampProjectId
            )

            // Pre-select if todolistId is already set
            if !todolistId.isEmpty, let id = Int(todolistId) {
                selectedTodolist = todolists.first { $0.id == id }
            }

            isLoadingTodolists = false
        }
    }

    private func clearIntegration() {
        accessToken = ""
        accountId = ""
        accountName = ""
        basecampProjectId = ""
        basecampProjectName = ""
        todosetId = ""
        todolistId = ""
        todolistName = ""
        syncStatus = false
        syncComments = false
        selectedAccount = nil
        selectedBasecampProject = nil
        selectedTodolist = nil
        accounts = []
        basecampProjects = []
        todolists = []
    }

    private func saveSettings() {
        Task {
            let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)

            let result = await viewModel.updateBasecampSettings(
                projectId: project.id,
                basecampAccessToken: trimmedToken.isEmpty ? "" : trimmedToken,
                basecampAccountId: accountId.isEmpty ? "" : accountId,
                basecampAccountName: accountName.isEmpty ? "" : accountName,
                basecampProjectId: basecampProjectId.isEmpty ? "" : basecampProjectId,
                basecampProjectName: basecampProjectName.isEmpty ? "" : basecampProjectName,
                basecampTodosetId: todosetId.isEmpty ? "" : todosetId,
                basecampTodolistId: todolistId.isEmpty ? "" : todolistId,
                basecampTodolistName: todolistName.isEmpty ? "" : todolistName,
                basecampSyncStatus: syncStatus,
                basecampSyncComments: syncComments,
                basecampIsActive: isActive
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
    BasecampSettingsView(
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
