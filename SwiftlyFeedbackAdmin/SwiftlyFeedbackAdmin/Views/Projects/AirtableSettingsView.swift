import SwiftUI

struct AirtableSettingsView: View {
    let project: Project
    @Bindable var viewModel: ProjectViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var token: String
    @State private var baseId: String
    @State private var baseName: String
    @State private var tableId: String
    @State private var tableName: String
    @State private var syncStatus: Bool
    @State private var syncComments: Bool
    @State private var statusFieldId: String
    @State private var votesFieldId: String
    @State private var titleFieldId: String
    @State private var descriptionFieldId: String
    @State private var categoryFieldId: String
    @State private var isActive: Bool
    @State private var showingTokenInfo = false

    // Base, table, and field selection state
    @State private var bases: [AirtableBase] = []
    @State private var tables: [AirtableTable] = []
    @State private var fields: [AirtableField] = []
    @State private var selectedBase: AirtableBase?
    @State private var selectedTable: AirtableTable?
    @State private var selectedStatusField: AirtableField?
    @State private var selectedVotesField: AirtableField?

    @State private var isLoadingBases = false
    @State private var isLoadingTables = false
    @State private var isLoadingFields = false
    @State private var basesError: String?
    @State private var showPaywall = false

    init(project: Project, viewModel: ProjectViewModel) {
        self.project = project
        self.viewModel = viewModel
        _token = State(initialValue: project.airtableToken ?? "")
        _baseId = State(initialValue: project.airtableBaseId ?? "")
        _baseName = State(initialValue: project.airtableBaseName ?? "")
        _tableId = State(initialValue: project.airtableTableId ?? "")
        _tableName = State(initialValue: project.airtableTableName ?? "")
        _syncStatus = State(initialValue: project.airtableSyncStatus)
        _syncComments = State(initialValue: project.airtableSyncComments)
        _statusFieldId = State(initialValue: project.airtableStatusFieldId ?? "")
        _votesFieldId = State(initialValue: project.airtableVotesFieldId ?? "")
        _titleFieldId = State(initialValue: project.airtableTitleFieldId ?? "")
        _descriptionFieldId = State(initialValue: project.airtableDescriptionFieldId ?? "")
        _categoryFieldId = State(initialValue: project.airtableCategoryFieldId ?? "")
        _isActive = State(initialValue: project.airtableIsActive)
    }

    private var hasChanges: Bool {
        token != (project.airtableToken ?? "") ||
        baseId != (project.airtableBaseId ?? "") ||
        baseName != (project.airtableBaseName ?? "") ||
        tableId != (project.airtableTableId ?? "") ||
        tableName != (project.airtableTableName ?? "") ||
        syncStatus != project.airtableSyncStatus ||
        syncComments != project.airtableSyncComments ||
        statusFieldId != (project.airtableStatusFieldId ?? "") ||
        votesFieldId != (project.airtableVotesFieldId ?? "") ||
        titleFieldId != (project.airtableTitleFieldId ?? "") ||
        descriptionFieldId != (project.airtableDescriptionFieldId ?? "") ||
        categoryFieldId != (project.airtableCategoryFieldId ?? "") ||
        isActive != project.airtableIsActive
    }

    private var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !tableId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                        Text("When disabled, Airtable sync will be paused.")
                    }
                }

                Section {
                    SecureField("Personal Access Token", text: $token)
                        .onChange(of: token) { _, newValue in
                            if !newValue.isEmpty && bases.isEmpty {
                                loadBases()
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
                    Text("Create a personal access token at airtable.com/create/tokens with the scopes: data.records:read, data.records:write, schema.bases:read.")
                }

                if hasToken {
                    Section {
                        if isLoadingBases {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading bases...")
                                    .foregroundStyle(.secondary)
                            }
                        } else if let error = basesError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                            Button("Retry") {
                                loadBases()
                            }
                        } else {
                            Picker("Base", selection: $selectedBase) {
                                Text("Select Base").tag(nil as AirtableBase?)
                                ForEach(bases) { base in
                                    Text(base.name).tag(base as AirtableBase?)
                                }
                            }
                            .onChange(of: selectedBase) { _, newValue in
                                if let base = newValue {
                                    baseId = base.id
                                    baseName = base.name
                                    loadTables(baseId: base.id)
                                } else {
                                    baseId = ""
                                    baseName = ""
                                    tables = []
                                    selectedTable = nil
                                    tableId = ""
                                    tableName = ""
                                    fields = []
                                }
                            }
                        }
                    } header: {
                        Text("Target Base")
                    } footer: {
                        if isConfigured {
                            Text("Selected: \(baseName)")
                        } else {
                            Text("Select the Airtable base where records will be created.")
                        }
                    }
                }

                if !baseId.isEmpty {
                    Section {
                        if isLoadingTables {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading tables...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("Table", selection: $selectedTable) {
                                Text("Select Table").tag(nil as AirtableTable?)
                                ForEach(tables) { table in
                                    Text(table.name).tag(table as AirtableTable?)
                                }
                            }
                            .onChange(of: selectedTable) { _, newValue in
                                if let table = newValue {
                                    tableId = table.id
                                    tableName = table.name
                                    // Save base and table first, then load fields
                                    saveBaseAndTable {
                                        loadFields()
                                    }
                                } else {
                                    tableId = ""
                                    tableName = ""
                                    fields = []
                                }
                            }
                        }
                    } header: {
                        Text("Target Table")
                    } footer: {
                        if !tableId.isEmpty {
                            Text("Selected: \(tableName)")
                        } else {
                            Text("Select the table where new records will be added.")
                        }
                    }
                }

                if isConfigured && !fields.isEmpty {
                    Section {
                        fieldPicker(
                            label: "Title Field",
                            selection: $titleFieldId,
                            allowedTypes: ["singleLineText", "multilineText", "richText"]
                        )
                        fieldPicker(
                            label: "Description Field",
                            selection: $descriptionFieldId,
                            allowedTypes: ["singleLineText", "multilineText", "richText"]
                        )
                        fieldPicker(
                            label: "Category Field",
                            selection: $categoryFieldId,
                            allowedTypes: ["singleLineText", "multilineText", "richText", "singleSelect"]
                        )
                    } header: {
                        Text("Field Mapping (Required)")
                    } footer: {
                        Text("Map feedback fields to your Airtable columns. Use field names, not IDs.")
                    }

                    Section {
                        fieldPicker(
                            label: "Status Field",
                            selection: $statusFieldId,
                            allowedTypes: ["singleLineText", "singleSelect"]
                        )
                        fieldPicker(
                            label: "Votes Field",
                            selection: $votesFieldId,
                            allowedTypes: ["number"]
                        )
                    } header: {
                        Text("Sync Fields (Optional)")
                    } footer: {
                        Text("These fields will be synced when status or votes change.")
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
                            Text("Loading fields...")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Field Mapping")
                    }
                }

                if isConfigured {
                    Section {
                        Button(role: .destructive) {
                            clearIntegration()
                        } label: {
                            Label("Remove Airtable Integration", systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Airtable Integration")
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
            .alert("Get Your Airtable Access Token", isPresented: $showingTokenInfo) {
                Button("Open Airtable Tokens") {
                    if let url = URL(string: "https://airtable.com/create/tokens") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Go to airtable.com/create/tokens\n2. Create a new personal access token\n3. Add scopes: data.records:read, data.records:write, schema.bases:read\n4. Select the bases you want to integrate\n5. Copy and paste the token here")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(requiredTier: .pro)
            }
            .task {
                if hasToken {
                    loadBases()
                }
            }
        }
    }

    @ViewBuilder
    private func fieldPicker(
        label: String,
        selection: Binding<String>,
        allowedTypes: [String]
    ) -> some View {
        let filteredFields = fields.filter { allowedTypes.contains($0.type) }
        Picker(label, selection: selection) {
            Text("None").tag("")
            ForEach(filteredFields) { field in
                Text("\(field.name) (\(field.type))").tag(field.name)
            }
        }
    }

    private func loadBases() {
        guard hasToken else { return }

        isLoadingBases = true
        basesError = nil

        Task {
            // First save the token so the API can use it
            let result = await viewModel.updateAirtableSettings(
                projectId: project.id,
                airtableToken: token.trimmingCharacters(in: .whitespacesAndNewlines),
                airtableBaseId: nil,
                airtableBaseName: nil,
                airtableTableId: nil,
                airtableTableName: nil,
                airtableSyncStatus: nil,
                airtableSyncComments: nil,
                airtableStatusFieldId: nil,
                airtableVotesFieldId: nil,
                airtableTitleFieldId: nil,
                airtableDescriptionFieldId: nil,
                airtableCategoryFieldId: nil,
                airtableIsActive: nil
            )

            if result == .success {
                bases = await viewModel.loadAirtableBases(projectId: project.id)
                if bases.isEmpty {
                    basesError = "No bases found. Make sure your token has the correct scopes and base access."
                } else {
                    // Pre-select if baseId is already set
                    if !baseId.isEmpty {
                        selectedBase = bases.first { $0.id == baseId }
                        if selectedBase != nil {
                            loadTables(baseId: baseId)
                        }
                    }
                }
            } else if result == .paymentRequired {
                showPaywall = true
            } else {
                basesError = viewModel.errorMessage ?? "Failed to verify token"
            }

            isLoadingBases = false
        }
    }

    private func loadTables(baseId: String) {
        isLoadingTables = true
        Task {
            tables = await viewModel.loadAirtableTables(projectId: project.id, baseId: baseId)

            // Pre-select if tableId is already set
            if !tableId.isEmpty {
                selectedTable = tables.first { $0.id == tableId }
                if selectedTable != nil {
                    // Save and then load fields
                    saveBaseAndTable {
                        loadFields()
                    }
                }
            }

            isLoadingTables = false
        }
    }

    private func saveBaseAndTable(completion: @escaping () -> Void) {
        Task {
            let result = await viewModel.updateAirtableSettings(
                projectId: project.id,
                airtableToken: nil,
                airtableBaseId: baseId,
                airtableBaseName: baseName,
                airtableTableId: tableId,
                airtableTableName: tableName,
                airtableSyncStatus: nil,
                airtableSyncComments: nil,
                airtableStatusFieldId: nil,
                airtableVotesFieldId: nil,
                airtableTitleFieldId: nil,
                airtableDescriptionFieldId: nil,
                airtableCategoryFieldId: nil,
                airtableIsActive: nil
            )
            if result == .success {
                completion()
            }
        }
    }

    private func loadFields() {
        isLoadingFields = true
        Task {
            fields = await viewModel.loadAirtableFields(projectId: project.id)
            isLoadingFields = false
        }
    }

    private func clearIntegration() {
        token = ""
        baseId = ""
        baseName = ""
        tableId = ""
        tableName = ""
        syncStatus = false
        syncComments = false
        statusFieldId = ""
        votesFieldId = ""
        titleFieldId = ""
        descriptionFieldId = ""
        categoryFieldId = ""
        selectedBase = nil
        selectedTable = nil
        bases = []
        tables = []
        fields = []
    }

    private func saveSettings() {
        Task {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

            let result = await viewModel.updateAirtableSettings(
                projectId: project.id,
                airtableToken: trimmedToken.isEmpty ? "" : trimmedToken,
                airtableBaseId: baseId.isEmpty ? "" : baseId,
                airtableBaseName: baseName.isEmpty ? "" : baseName,
                airtableTableId: tableId.isEmpty ? "" : tableId,
                airtableTableName: tableName.isEmpty ? "" : tableName,
                airtableSyncStatus: syncStatus,
                airtableSyncComments: syncComments,
                airtableStatusFieldId: statusFieldId.isEmpty ? "" : statusFieldId,
                airtableVotesFieldId: votesFieldId.isEmpty ? "" : votesFieldId,
                airtableTitleFieldId: titleFieldId.isEmpty ? "" : titleFieldId,
                airtableDescriptionFieldId: descriptionFieldId.isEmpty ? "" : descriptionFieldId,
                airtableCategoryFieldId: categoryFieldId.isEmpty ? "" : categoryFieldId,
                airtableIsActive: isActive
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
    AirtableSettingsView(
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
